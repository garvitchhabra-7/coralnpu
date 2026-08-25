# C to Simulated Execution — Full Pipeline Trace

Tracing `hello_world_add_floats.cc` through every stage from C source to Verilator simulation.

---

## 1. C Source

**File:** `examples/hello_world_add_floats.cc`

```c
float input1[8] __attribute__((section(".data")));
float input2[8] __attribute__((section(".data")));
float output[8] __attribute__((section(".data")));

int main() {
  for (int i = 0; i < 8; i++)
    output[i] = input1[i] + input2[i];
  return 0;
}
```

Three float arrays placed explicitly in `.data` (DTCM). The loop adds them element-wise. No I/O — the simulator inspects the return value to determine pass/fail.

---

## 2. Bazel Build Rule

**File:** `examples/BUILD.bazel`

```python
load("//rules:coralnpu_v2.bzl", "coralnpu_v2_binary")

coralnpu_v2_binary(
    name = "coralnpu_v2_hello_world_add_floats",
    srcs = ["hello_world_add_floats.cc"],
)
```

The `coralnpu_v2_binary` macro (defined in `rules/coralnpu_v2.bzl`) does three things:

1. **Platform transition** — applies a Bazel `transition` that switches the build to `//platforms:coralnpu_v2`, activating the RISC-V clang cross-compiler toolchain (`rv32imf_zve32x_zicsr_zifencei_zbb`).

2. **Linker script generation** — calls `generate_linker_script` from the template `toolchain/coralnpu_tcm.ld.tpl` with default TCM sizes: 8 KB ITCM, 32 KB DTCM, 128-byte stack.

3. **CRT linkage** — adds `//toolchain/crt` as a dependency, pulling in the startup assembly and runtime glue.

### Build outputs

```
coralnpu_v2_hello_world_add_floats.elf   # linked ELF
coralnpu_v2_hello_world_add_floats.bin   # raw binary (objcopy -O binary)
coralnpu_v2_hello_world_add_floats.vmem  # Verilog hex (srec_cat)
```

---

## 3. Memory Layout

**File:** `toolchain/coralnpu_tcm.ld.tpl`

The generated linker script maps sections onto the core's tightly-coupled memories:

| Address       | Region          | Contents                                          |
|---------------|-----------------|---------------------------------------------------|
| `0x0000000`   | ITCM (8 KB)     | `._init`, `.text`, `.rodata`, init/fini arrays    |
| `0x0010000`   | DTCM (32 KB)    | `.data` (input1, input2, output), `.bss`, stack   |
| `0x0030000`   | CSR/Peripheral  | Memory-mapped control registers                   |
| `0x2000000`   | EXTMEM (4 MB)   | External memory region (unused here)              |

Key linker symbols used by CRT:
- `_start` — entry point (ITCM)
- `__stack_end__` — top of stack (DTCM)
- `__bss_start__` / `__bss_end__` — BSS bounds for zeroing
- `_ret` — 4-byte slot in `.data` where CRT stores `main()`'s return value
- `_global_pointer` — set to `.data + 0x800` for GP-relative addressing

---

## 4. Cross-Compilation

The platform transition selects a clang-based RISC-V cross-compiler from `toolchain/`. The build rule uses Bazel's `cc_common.compile` and `cc_common.link` APIs:

1. **Compile** — produces `.o` files targeting `rv32imf` with Zve32x, Zicsr, Zifencei, and Zbb extensions. The float addition loop compiles to `flw`/`fadd.s`/`fsw` instructions using the F extension's hardware FPU.

2. **Link** — links the object file with CRT startup code using the generated linker script (`-Wl,-T,<name>.ld`), producing an ELF.

3. **objcopy** — strips the ELF into a raw binary (`.bin`).

4. **srec_cat** — converts the binary to a `.vmem` file (Verilog `$readmemh` format) with 32-bit word byte-swapping.

---

## 5. CRT Startup Sequence

**Files:** `toolchain/crt/coralnpu_start.S`, `toolchain/crt/crt.S`

The CPU begins execution at `_start`. The full boot sequence before `main()`:

```asm
_start:
  csrw minstret, 0          // reset perf counters
  la   sp, __stack_end__     // set stack pointer (DTCM)
  la   gp, _global_pointer   // set global pointer

  // zero all 26 remaining GPRs (tp, t1-t6, s0-s11, a1-a7)

  la   a0, __bss_start__     // zero .bss section
  la   a1, __bss_end__
  call crt_section_clear     // word-by-word zero (crt.S)

  // run C++ constructors from __init_array

  la   t0, coralnpu_exception_handler
  csrw mtvec, t0             // install trap vector
  li   t0, 0x6600
  csrrs zero, mstatus, t0   // set FS=Dirty, VS=Dirty (enable FPU/vector)

  call main                  // ← your code runs here

  // on return:
  //   run C++ destructors (__fini_array, __cxa_finalize)
  //   store retval to _ret in DTCM
  //   retval==0 → mpause (0x08000073, clean halt)
  //   retval!=0 → ebreak (failure trap)
```

`crt_section_clear` in `crt.S` zeroes memory word-by-word with alignment checks. The custom `mpause` instruction (`0x08000073`) signals a clean halt to the simulator.

---

## 6. RTL: Chisel → SystemVerilog

**Source:** `hdl/chisel/src/coralnpu/`

The hardware under test is the **CoreMiniAxi** variant — scalar pipeline + FPU, no RVV vector unit. Chisel sources are compiled to SystemVerilog by the `chisel_cc_library` Bazel rule.

### Scalar Pipeline (3-stage, 4-wide dispatch)

```
Fetch    128-bit bus fetch → up to 4 instructions/cycle
  ↓
Decode   Scoreboard tracks RAW/WAW hazards, dispatches to:
  ├─ ALU ×4   integer add/logic/shift (1 per lane)
  ├─ BRU      branch/jump
  ├─ MLU      multiply (shared)
  ├─ DVU      divide (shared)
  ├─ FPU      fadd.s, fmul.s, ... (F extension)
  └─ LSU      flw/fsw → slot-based state machine → TLUL bus
  ↓
Writeback results → register file / FP register file
```

### Execution path for this program

1. **Fetch** pulls `flw`/`fadd.s`/`fsw` loop from ITCM (128-bit fetch → up to 4 instr/cycle)
2. **Decode** dispatches float loads to LSU, `fadd.s` to FPU
3. **LSU** issues TileLink-UL reads to DTCM for `input1[i]` and `input2[i]`
4. **FPU** computes the single-precision sum
5. **LSU** writes `output[i]` back to DTCM via TileLink-UL

### Bus fabric

Internal bus routing uses TileLink-UL (`hdl/chisel/src/bus/`):
- `TileLinkUL.scala` — protocol definitions
- `TlulSocket1N.scala` / `TlulSocketM1.scala` — 1:N and M:1 crossbar sockets
- `Fabric.scala` — address decode and routing

`CoreAxi.scala` wraps the core with AXI4↔TLUL bridges for the external interface.

### Key RTL files

| File                    | Role                                        |
|-------------------------|---------------------------------------------|
| `Core.scala`            | Connects scalar + FPU + caches + TCM        |
| `CoreAxi.scala`         | Adds AXI4 external interface                |
| `Parameters.scala`      | All RTL configuration knobs                 |
| `scalar/Fetch.scala`    | Instruction fetch (128-bit, optional L0)    |
| `scalar/Decode.scala`   | 4-wide decode + scoreboard                  |
| `scalar/Fpu.scala`      | Scalar floating-point unit                  |
| `scalar/Lsu.scala`      | Load/Store with slot-based state machine    |

---

## 7. Verilator Simulation

**File:** `tests/verilator_sim/coralnpu/core_mini_axi_sim.cc`

The Verilator simulator is a C++/SystemC testbench. It instantiates the Verilated `CoreMiniAxi` model inside `CoreMiniAxi_tb`, which provides AXI-to-TLM bridges and an external memory crossbar.

### Build & run

```bash
# Build the simulator
bazel build //tests/verilator_sim:core_mini_axi_sim

# Build the binary
bazel build //examples:coralnpu_v2_hello_world_add_floats

# Run
bazel-bin/tests/verilator_sim/core_mini_axi_sim \
    --binary bazel-bin/examples/coralnpu_v2_hello_world_add_floats.elf
```

### Simulation boot sequence

```cpp
CoreMiniAxi_tb tb(...);
sc_start(SC_ZERO_TIME);    // run Verilog initial blocks

tb.LoadElfSync(binary);    // parse ELF, write sections into ITCM/DTCM SRAMs
tb.ClockGateSync(false);   // enable clock
tb.ResetAsync(false);      // release reset — CPU starts fetching at _start

halted_cv.Wait(...);       // block until core halts (mpause or ebreak)
tb.CheckStatusSync();      // verify: _ret == 0 → pass
```

**LoadElfSync** parses the ELF's program headers and writes each loadable segment into the RTL model's SRAM arrays — either via AXI transactions or the DPI-based SRAM backdoor (`hdl/verilog/sram_backdoor.cc`) when `--backdoor_load` is set.

After reset deasserts, the simulated CPU begins executing at `_start` exactly as real silicon would. The core runs the CRT, calls `main()`, adds the 8 float pairs, returns 0, and the CRT executes `mpause`. The testbench's halted callback fires, the main thread reads `_ret` from DTCM, confirms it's 0, and the sim exits successfully.

### Optional flags

| Flag              | Effect                                  |
|-------------------|-----------------------------------------|
| `--cycles N`      | Max simulation cycles (default 100M)    |
| `--trace`         | Dump VCD waveform                       |
| `--debug_axi`     | Log AXI traffic                         |
| `--instr_trace`   | Log executed instructions to console    |
| `--backdoor_load` | Fast SRAM loading via DPI backdoor      |

---

## End-to-End Summary

```
C source
  → Bazel platform transition to rv32imf
    → clang cross-compile (flw/fadd.s/fsw)
      → link with CRT + TCM linker script
        → ELF loaded into Verilated CoreMiniAxi SRAMs
          → 3-stage scalar pipeline executes FPU loop
            → CRT halts via mpause
              → testbench confirms _ret == 0
```

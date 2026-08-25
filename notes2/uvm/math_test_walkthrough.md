# UVM Co-Simulation Walkthrough: math.cc

A walkthrough of running `tests/cocotb/math.cc` through the UVM testbench,
explaining what happens at each phase and how the co-simulation checker works.

## The Test Program

```c
#pragma GCC optimize("O0")

int math(int a, int b) {
    return ((2 * a) + (3 * b * b));
}

int main(int argc, char** argv) {
    int sum = 0;
    for (int i = 0, j = 0; i < 2; ++i, ++j) {
        sum += math(i, j);
    }
    return (sum == 5) ? 0 : 1;
}
```

Self-contained (no external inputs needed), exercises integer multiply/add
in a loop, and self-checks the result. Good for seeing the co-simulation in
action.

## Build and Run

```bash
# Build the ELF
bazel build //tests/cocotb:math
cp bazel-bin/tests/cocotb/math.elf tests/uvm/bin/

# Run with high verbosity to see co-sim output
cd tests/uvm
make run TEST_ELF=$(pwd)/bin/math.elf UVM_VERBOSITY=UVM_HIGH
```

## Key Terminology

- **GPR** — General Purpose Register. The 32 integer registers in RISC-V
  (x0-x31). When the log says `GPR[x2] match`, it means the value written
  to integer register x2 by the RTL matched what MPACT computed. Similarly,
  FPR = Floating Point Register (f0-f31), VPR = Vector Register (v0-v31).

- **Kickoff Sequence** — The UVM testbench acting as an external host to boot
  the core. The core powers up halted/gated and needs three AXI writes to
  start: set the PC, ungate the clock, release internal reset. This is what
  a real SoC's CPU or debug controller would do to bring up the NPU. The
  code is in `coralnpu_kickoff_write_seq` (`coralnpu_test_pkg.sv`). In
  cocotb, the equivalent is `core_mini_axi.execute_from(entry_point)`.

- **CRT (C Runtime) Startup** — When you compile `math.cc`, the compiler
  links in startup code from `toolchain/crt/` that runs *before* `main()`.
  This is standard for any C program — `main()` is never the true entry
  point. On this core, the CRT:
  1. Reads `mcycle`/`mcycleh` to snapshot the boot cycle count
  2. Sets up the stack pointer (x2/sp) pointing to top of DTCM
  3. Zeros all registers x3-x31 (RISC-V doesn't guarantee initial state)
  4. Sets up `argc`/`argv` for the C calling convention
  5. Writes a stack canary (`0x0BADD00D`) to detect stack overflow
  6. Calls `main()`
  7. After `main()` returns, reads `mcycle` again and halts the core

  The CRT is linked automatically by the `coralnpu_v2_binary` Bazel rule.

## Phase-by-Phase Log Analysis

### Phase 1: Setup (0 - 55ns)

```
@ 0:     [TB_TOP] Reset Asserted
@ 45ns:  [TB_TOP] Reset Deasserted
@ 55ns:  [coralnpu_base_test] Loaded ELF via backdoor: .../math.elf
@ 55ns:  [coralnpu_cosim_checker] Initializing Co-Sim for .../math.elf
```

- Reset held for 5 clocks, then released.
- `sram_load_elf()` writes the binary directly into the DUT's SRAM via DPI
  backdoor (bypasses AXI).
- MPACT ISS also loads the same ELF — both start from identical state.

### Phase 2: Kickoff Sequence (55ns - 195ns)

Three AXI writes to the CSR region (`0x30000`):

| Write | Address    | Data | Purpose |
|-------|-----------|------|---------|
| 1     | `0x30004` | 0x0  | Set program counter (entry point) |
| 2     | `0x30000` | 0x1  | Release clock gate |
| 3     | `0x30000` | 0x0  | Release internal reset |

After write 3, the core starts fetching and executing instructions from PC=0.

### Phase 3: CRT Startup (265ns - 425ns)

The first instructions are C runtime startup, not `main()`.

**mcycle/mcycleh reads (PC 0x0-0xc):**
```
[COSIM_DIRTY] GPR[x10] marked DIRTY at PC 0x00000008 (varying=1, consumes=0)
[COSIM_SKIP]  Skipping GPR[x10] comparison at PC 0x00000008 due to dirty mask
[COSIM_DIRTY] GPR[x11] marked DIRTY at PC 0x0000000c (varying=1, consumes=0)
[COSIM_SKIP]  Skipping GPR[x11] comparison at PC 0x0000000c due to dirty mask
```

The CRT reads performance counters (`mcycle`, `mcycleh`). These will naturally
differ between RTL and ISS (different cycle counts), so the dirty-register
tracker marks x10 and x11 as "tainted" and skips comparison. This prevents
false mismatches.

**Stack pointer setup (PC 0x10):**
```
[MPACT_MATCH] GPR[x2] match at PC 0x00000010. RTL: 0x00018010, MPACT: 0x00018010
```

`auipc x2, 0x18` — sets the stack pointer. Both RTL and MPACT agree.

**Register zeroing (PC 0x14-0x84):**

The CRT zeros registers x3-x31. The core retires up to 4 instructions per
clock — you can see this in the log where multiple channels fire at the same
timestamp:

```
@ 355000: Instruction retired on channel 0, PC: 0x0000001c
@ 355000: Instruction retired on channel 1, PC: 0x00000020
@ 355000: Instruction retired on channel 2, PC: 0x00000024
@ 355000: Instruction retired on channel 3, PC: 0x00000028
```

This is the 4-wide dispatch pipeline in action.

### Phase 4: main() and math() (425ns - 3265ns)

**Calling main (PC 0x88-0x94):**
```
[MPACT_MATCH] GPR[x10] match at PC 0x00000088. RTL: 0x00010010, MPACT: 0x00010010
[MPACT_MATCH] GPR[x11] match at PC 0x0000008c. RTL: 0x0001008c, MPACT: 0x0001008c
[MPACT_MATCH] GPR[x1]  match at PC 0x00000094. RTL: 0x00000098, MPACT: 0x00000098
```

argc/argv setup, then `jal main` with return address x1 = 0x98.

**Stack canary (PC 0xd4-0xd8):**
```
[MPACT_MATCH] GPR[x10] match at PC 0x000000d4. RTL: 0x0badd000, MPACT: 0x0badd000
[MPACT_MATCH] GPR[x10] match at PC 0x000000d8. RTL: 0x0badd00d, MPACT: 0x0badd00d
```

The CRT writes `0x0BADD00D` as a stack protection canary.

**Loop body — calling math() twice:**

The loop calls `math(i, j)` for i=0..1. Each call jumps to the `math()`
function body (PC ~0x190-0x20c), executes the multiply/add arithmetic, and
returns. The co-sim checker verifies every register write along the way.

```
[MPACT_MATCH] GPR[x1] match at PC 0x000000f0. RTL: 0x000000f4, MPACT: 0x000000f4
  ... (math() body executes, all matches) ...
[MPACT_MATCH] GPR[x1] match at PC 0x0000020c. RTL: 0x000000f4, MPACT: 0x000000f4
```

### Phase 5: Shutdown (3425ns - 3470ns)

```
[COSIM_DIRTY] GPR[x10] marked DIRTY at PC 0x00000134 (varying=1, consumes=0)
[COSIM_SKIP]  Skipping GPR[x10] comparison at PC 0x00000134 due to dirty mask
[COSIM_DIRTY] GPR[x11] marked DIRTY at PC 0x00000138 (varying=1, consumes=0)
[COSIM_SKIP]  Skipping GPR[x11] comparison at PC 0x00000138 due to dirty mask

** UVM TEST PASSED **
```

CRT epilogue reads mcycle/mcycleh again (measuring elapsed time), then the
core halts. The DUT's `halted` signal goes high, the test detects it, and
reports PASS.

## Summary

| Metric | Value |
|--------|-------|
| Total simulation time | 3.47 us (3470 ns) |
| Instructions retired and compared | ~200 |
| Dirty-register skips | 4 (all mcycle/mcycleh) |
| Co-sim mismatches | 0 |
| Max retirement width observed | 4 instructions/cycle |
| UVM errors | 0 |

## What a Failure Would Look Like

If the RTL had a bug (e.g., wrong ALU result), you would see:

```
UVM_ERROR [COSIM_GPR_MISMATCH] GPR[x15] mismatch at PC 0x000001a0.
    RTL: 0x00000006, MPACT: 0x00000005
```

The checker would flag the exact PC, register, and both values — pinpointing
the failing instruction.

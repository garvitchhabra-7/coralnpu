# Coral NPU Software Tutorial

Reference: https://developers.google.com/coral/guides/software/programming

## Step 1: The C Program

Source: `tests/cocotb/tutorial/program.cc`

### Data Buffers

Three 8-element `uint32_t` arrays are placed in DTCM using the `.data` section attribute:

```c
uint32_t input1_buffer[8] __attribute__((section(".data")));
uint32_t input2_buffer[8] __attribute__((section(".data")));
uint32_t output_buffer[8] __attribute__((section(".data")));
```

`__attribute__((section(".data")))` ensures these buffers are allocated in DTCM, where the host can read/write them before and after execution.

### Computation

`main()` performs element-wise addition of the two input buffers into the output buffer:

```c
for (int i = 0; i < 8; i++) {
  output_buffer[i] = input1_buffer[i] + input2_buffer[i];
}
```

Returning from `main()` halts the core.

## Step 2: Building the ELF

```bash
bazel build //tests/cocotb/tutorial:coralnpu_v2_program
```

The `coralnpu_v2_program` target uses the `coralnpu_v2_binary` rule, which handles the platform transition to the RISC-V toolchain. From `tests/cocotb/tutorial/BUILD`:

```python
coralnpu_v2_binary(
    name = "coralnpu_v2_program",
    srcs = ["program.cc"],
)
```

This rule (defined in `rules/coralnpu_v2.bzl`) cross-compiles the source to a RISC-V ELF targeting the `//platforms:coralnpu_v2` platform. The resulting binary has loadable sections — `.text` (code) mapped to ITCM and `.data` (buffers) mapped to DTCM.

The ELF is a binary format, so you can't read it directly. Use `readelf` to inspect sections:

```bash
readelf -S bazel-bin/tests/cocotb/tutorial/coralnpu_v2_program
```

This shows each section's name, target address, and size.

Note: The `coralnpu_v2_binary` rule automatically links the CRT (`//toolchain/crt`) into the binary. The CRT (`toolchain/crt/coralnpu_start.S`) provides startup code that calls `main()` and halts the core via `mpause` when it returns. This is why `wait_for_halted` works in the testbench — it's not something your program needs to do explicitly.

## Step 3: The Cocotb Testbench

Source: `tests/cocotb/tutorial/tutorial.py`

The testbench loads the ELF into simulated memory, writes inputs, runs the program, and reads back results.

### Setup

```python
core_mini_axi = CoreMiniAxiInterface(dut)
await core_mini_axi.init()
await core_mini_axi.reset()
cocotb.start_soon(core_mini_axi.clock.start())
```

Creates the AXI interface to the simulated core, initializes it, and starts the clock.

### Load ELF and Locate Buffers

```python
r = runfiles.Create()
elf_path = r.Rlocation(
    "coralnpu_hw/tests/cocotb/tutorial/coralnpu_v2_program.elf")
with open(elf_path, "rb") as f:
    entry_point = await core_mini_axi.load_elf(f)
    inputs1_addr = core_mini_axi.lookup_symbol(f, "input1_buffer")
    inputs2_addr = core_mini_axi.lookup_symbol(f, "input2_buffer")
    outputs_addr = core_mini_axi.lookup_symbol(f, "output_buffer")
```

The ELF is located via Bazel runfiles (the path is `<workspace_name>/<package>/<target>.elf`). `load_elf` writes the ELF's loadable sections into ITCM/DTCM and returns the entry point address. `lookup_symbol` finds the DTCM addresses of the named C variables from the ELF's symbol table.

### Write Inputs

```python
input1_data = np.arange(8, dtype=np.uint32)        # [0, 1, 2, ..., 7]
input2_data = 8994 * np.ones(8, dtype=np.uint32)    # [8994, 8994, ..., 8994]
await core_mini_axi.write(inputs1_addr, input1_data)
await core_mini_axi.write(inputs2_addr, input2_data)
```

Writes test data to the input buffer addresses via AXI before execution starts.

### Execute and Wait

```python
await core_mini_axi.execute_from(entry_point)
await core_mini_axi.wait_for_halted()
```

Starts the core at the entry point. `wait_for_halted` blocks until the CRT issues `mpause` after `main()` returns.

### Read Output

```python
rdata = (await core_mini_axi.read(outputs_addr, 4 * 8)).view(np.uint32)
print(f"I got {rdata}")
```

Reads 32 bytes (8 × 4-byte uint32) from the output buffer address. Expected output: `[8994 8995 8996 8997 8998 8999 9000 9001]`.

### Running the Test

```bash
bazel run //tests/cocotb/tutorial:tutorial
```

## Cocotb Testbench vs Verilator Sim

Both use Verilator to simulate the same RTL, but they differ in who provides the test data:

- **Verilator sim**: The program must be self-contained — inputs are hardcoded or generated internally. You just hand it an ELF and it runs to completion. No external control.
- **Cocotb testbench** (this tutorial): Python injects inputs and reads outputs via AXI. The same program can be tested with different data without recompiling.

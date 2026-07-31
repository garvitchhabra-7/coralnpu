# Simulating Design with Verilator

## Cocotb tests vs Verilator sim

Both use Verilator to simulate the same RTL. The difference is who drives the test.

- **Verilator sim** (`tests/verilator_sim/`): C++/SystemC testbench that acts like a minimal SoC. Loads an ELF binary into memory, releases reset, and lets the core run to completion. Test logic lives in the RISC-V binary (return 0 = pass). Black-box, end-to-end.
- **Cocotb tests** (`tests/cocotb/`): Python testbenches that drive RTL signals directly. Can poke AXI transactions, check registers, inject specific stimulus, and assert on cycle-level behavior. Test logic lives in Python. White-box, targeted.

## Run Cocotb test suite

```bash
bazel run //tests/cocotb:core_mini_axi_sim_cocotb
```

### Run a single test case

Pattern: `<suite>_<testcase>_<simulator>`

```bash
bazel test //tests/cocotb:core_mini_axi_sim_cocotb_core_mini_axi_basic_write_read_memory_verilator
```

### List all cocotb test targets

```bash
bazel query 'tests(//tests/cocotb/...)'
```

## Build a binary

```bash
bazel build //examples:coralnpu_v2_hello_world_add_floats
```

## Build the simulator

```bash
bazel build //tests/verilator_sim:core_mini_axi_sim
```

## Run binary on simulator

```bash
bazel-bin/tests/verilator_sim/core_mini_axi_sim \
  --binary bazel-out/k8-fastbuild-ST-dd8dc713f32d/bin/examples/coralnpu_v2_hello_world_add_floats.elf
```

### Useful flags

```bash
# Dump waveform trace (.fst file, open with GTKWave)
--trace

# Log every retired instruction to console
--instr_trace

# Show AXI bus traffic
--debug_axi
```

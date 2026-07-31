# Simulation Capabilities

The repo provides simulation at three levels of fidelity, plus a Python-driven cocotb test framework that runs on top of the RTL simulators. All are unified under Bazel.

## 1. ISS — MPACT Instruction Set Simulator

**Location:** `sw/coralnpu_sim/`

A pure software, functional model of the CoralNPU — no RTL involved. Wraps `coralnpu_v2_simulator` from the `@coralnpu_mpact` external dependency (MPACT is Google's RISC-V functional simulator framework). A pybind11 layer (`sw/coralnpu_sim/coralnpu_v2_sim_pybind.cc`) exposes the C++ simulator to Python.

This is the fastest simulation option — ideal for SW development, algorithm validation, and quick smoke tests without compiling any RTL.

### Capabilities

- **Load & run ELF binaries** with optional custom entry point
- **Single-step execution** (`step(n)`) and **cycle counting** (`get_cycle_count()`)
- **Software breakpoints** — set/clear at arbitrary addresses
- **Async halt** — stop a running simulation from another thread
- **Register read/write** by name (e.g. `"pc"`, `"t0"`)
- **Memory read/write** — byte-level, word-level, pointer-level (numpy arrays)
- **ELF symbol lookup** via `pyelftools` for data-driven tests
- **HTIF semihosting** support (printf/exit from bare-metal code)
- **Configurable memory map** via `LsuAccessRange` objects

### Default Memory Layout (highmem)

| Region | Start Address | Size |
|---|---|---|
| ITCM | `0x00000000` | 1 MB |
| DTCM | `0x00100000` | 1 MB |
| ExtMem | `0x20000000` | 4 MB |
| DDR | `0x80000000` | 128 MB |

### Usage

```python
from coralnpu_v2_sim_utils import CoralNPUV2Simulator

sim = CoralNPUV2Simulator(highmem_ld=True, exit_on_ebreak=True, semihost_htif=True)
entry, symbols = sim.get_elf_entry_and_symbol("program.elf", ["in_buf", "out_buf"])
sim.load_program("program.elf", entry)
sim.write_memory(symbols["in_buf"], input_data)
sim.run()
sim.wait()
output = sim.read_memory(symbols["out_buf"], length)
```

### Build & Test

```bash
bazel build //sw/coralnpu_sim:coralnpu_v2_sim
bazel test //sw/coralnpu_sim:coralnpu_v2_sim_test
```

### Key Files

| Path | Description |
|---|---|
| `sw/coralnpu_sim/coralnpu_v2_sim_pybind.cc` | Pybind11 wrapper around the C++ simulator |
| `sw/coralnpu_sim/coralnpu_v2_sim_utils.py` | Python helper class (`CoralNPUV2Simulator`) |
| `sw/coralnpu_sim/coralnpu_v2_sim_test.py` | Unit tests (vector add kernel, stepping, breakpoints, halt) |
| `rules/mpact.bzl` | Bazel rule for building MPACT with host clang transition |

---

## 2. Verilator RTL Simulation

**Location:** `tests/verilator_sim/`

Cycle-accurate RTL simulation using Verilator (open-source). A C++ testbench loads an ELF and runs it on the compiled Verilog netlist. No license required.

### Build the Simulator

```bash
# Scalar + float variant
bazel build //tests/verilator_sim:core_mini_axi_sim

# With RVV vector extension
bazel build //tests/verilator_sim:rvv_core_mini_axi_sim
```

### Run a Binary

```bash
bazel-bin/tests/verilator_sim/core_mini_axi_sim \
  --binary=<path/to/binary.elf>
```

### Key Files

| Path | Description |
|---|---|
| `tests/verilator_sim/BUILD` | Simulator targets and ELF-runner configs |
| `tests/verilator_sim/coralnpu/` | C++ testbench sources |
| `tests/verilator_sim/elf.cc` | ELF loader |
| `tests/verilator_sim/sysc_tb.h` | SystemC testbench wrapper |

---

## 3. VCS RTL Simulation

**Location:** `tests/vcs_sim/`

Commercial RTL simulation using Synopsys VCS. Supports FSDB waveform dumping and Verdi debug. Requires a VCS license and environment variables. All targets are gated behind `--config=vcs`.

### Build & Run

```bash
bazel build --config=vcs //tests/vcs_sim:core_mini_axi_sim

bazel run --config=vcs //tests/vcs_sim:core_mini_axi_sim -- \
  --binary=$(realpath bazel-bin/examples/coralnpu_v2_hello_world_add_floats.elf) \
  --trace
```

If you hit ccache conflicts:
```bash
bazel build --config=vcs --action_env=CCACHE_DISABLE=1 //tests/vcs_sim:core_mini_axi_sim
```

See `notes/running_vcs_sim.md` for the full VCS + Verdi workflow.

### Key Files

| Path | Description |
|---|---|
| `tests/vcs_sim/BUILD` | VCS simulator targets |
| `tests/vcs_sim/top.sv` | Top-level testbench wrapper |
| `rules/vcs.bzl` | VCS-specific Bazel rules |

---

## 4. Cocotb Test Framework

**Location:** `tests/cocotb/`

Python-driven RTL testbenches using cocotb, running on top of either Verilator or VCS as the simulator backend. This is where the bulk of functional verification lives.

### Verilator Models

Precompiled Verilator shared libraries are built as `verilator_cocotb_model` targets in `tests/cocotb/BUILD`:

| Target | RTL Module | Description |
|---|---|---|
| `//tests/cocotb:core_mini_axi_model` | `CoreMiniAxi` | Scalar + float, 8KB ITCM / 32KB DTCM |
| `//tests/cocotb:rvv_core_mini_axi_model` | `RvvCoreMiniAxi` | + RVV vector extension |
| `//tests/cocotb:rvv_core_mini_highmem_axi_model` | `RvvCoreMiniHighmemAxi` | 1MB ITCM + DTCM |
| `//tests/cocotb:rvv_core_mini_itcm512kb_dtcm512kb_axi_model` | `RvvCoreMini_ITCM512KB_DTCM512KBAxi` | 512KB each |

### Running Tests

```bash
# Full cocotb suite (Verilator backend)
bazel run //tests/cocotb:core_mini_axi_sim_cocotb

# Single testcase
bazel test //tests/cocotb:core_mini_axi_sim_cocotb_core_mini_axi_basic_write_read_memory_verilator

# RVV-specific suites
bazel run //tests/cocotb:rvv_assembly_cocotb_test
bazel run //tests/cocotb:rvv_arithmetic_cocotb_test
bazel run //tests/cocotb:rvv_ml_ops_cocotb_test
bazel run //tests/cocotb:rvv_load_store_test

# Same tests with VCS backend
bazel test --config=vcs //tests/cocotb:core_mini_axi_sim_cocotb
```

### Test Utilities

Shared Python helpers in `coralnpu_test_utils/`:

| File | Purpose |
|---|---|
| `coralnpu_test_utils/sim_test_fixture.py` | Base fixture class for cocotb tests |
| `coralnpu_test_utils/core_mini_axi_interface.py` | AXI bus driver |
| `coralnpu_test_utils/backdoor.py` | SRAM backdoor loading (bypass AXI) |
| `coralnpu_test_utils/rvv_type_util.py` | RVV vector type helpers |
| `coralnpu_test_utils/run_binary.py` | Helper to load and run an ELF in cocotb |
| `coralnpu_test_utils/axi_slave.py` | AXI slave responder |

### Updating Testcase Lists

When adding or removing `@cocotb.test` entries in Python test files, sync the BUILD file:

```bash
# Update a specific test file's testcase list
python3 utils/update_cocotb_tests.py <test.py> <BUILD> <VARIABLE_NAME> <target_name>

# Update all at once
python3 utils/update_all_cocotb_tests.py
```

Testcase lists in BUILD files are delimited by `# BEGIN_TESTCASES_FOR_<name>` / `# END_TESTCASES_FOR_<name>` markers.

---

## Summary

| Level | Tool | Location | Speed | Fidelity | License |
|---|---|---|---|---|---|
| ISS (functional) | MPACT | `sw/coralnpu_sim/` | Fastest | Instruction-accurate | Open |
| RTL (cycle-accurate) | Verilator | `tests/verilator_sim/` | Medium | Cycle-accurate | Open |
| RTL (verification) | VCS | `tests/vcs_sim/` | Slowest | Cycle-accurate + waveforms | Commercial |
| Test harness | cocotb | `tests/cocotb/` | Depends on backend | Depends on backend | Open |

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Coral NPU is an open-source ML accelerator IP based on 32-bit RISC-V (`rv32imf_zve32x_zicsr_zifencei_zbb`). RTL is written in Chisel (Scala) and compiled to SystemVerilog; simulation tests use cocotb (Python) backed by Verilator or VCS. The build system is Bazel 7.4.1.

## Essential Commands

### Building

```bash
# Build a RISC-V binary (auto-transitions to coralnpu_v2 platform)
bazel build //examples:coralnpu_v2_hello_world_add_floats

# Build the Verilator simulator (non-RVV, faster build)
bazel build //tests/verilator_sim:core_mini_axi_sim

# Run a binary on the simulator
bazel-bin/tests/verilator_sim/core_mini_axi_sim --binary <path/to/binary.elf>

# Emit Verilog for a specific RTL target
bazel build //hdl/chisel/src/coralnpu:core_mini_axi_cc_library_verilog
bazel build //hdl/chisel/src/coralnpu:rvv_core_mini_axi_cc_library_verilog
```

### Testing

```bash
# Run the main cocotb test suite (Verilator)
bazel run //tests/cocotb:core_mini_axi_sim_cocotb

# Run a specific cocotb testcase
bazel test //tests/cocotb:core_mini_axi_sim_cocotb_core_mini_axi_basic_write_read_memory_verilator

# Run Chisel unit tests
bazel test //hdl/chisel/src/coralnpu:coralnpu_scalar_tests
bazel test //hdl/chisel/src/coralnpu:coralnpu_rvv_tests
bazel test //hdl/chisel/src/coralnpu:coralnpu_float_tests

# Run bus/common unit tests
bazel test //hdl/chisel/src/bus:...
bazel test //hdl/chisel/src/common:...

# RVV-specific cocotb tests
bazel run //tests/cocotb:rvv_assembly_cocotb_test
bazel run //tests/cocotb:rvv_load_store_test
bazel run //tests/cocotb:rvv_arithmetic_cocotb_test
bazel run //tests/cocotb:rvv_ml_ops_cocotb_test

# VCS simulation (requires VCS license and env vars)
bazel test --config=vcs //tests/cocotb:core_mini_axi_sim_cocotb
# Workaround for ccache conflicts:
bazel test --config=vcs --action_env=CCACHE_DISABLE=1 //...
```

### Code Quality

```bash
# Lint Verilog (VCS-based; requires --config=vcs)
bazel build --config=vcs //hdl/chisel/src/coralnpu:core_mini_axi_cc_library_lint
```

Pre-upload hooks (run automatically on `repo upload`): `cpplint`, `pylint3`, `clang_format`, `buildifier`, `yapf-diff`.

### Updating Cocotb Testcase Lists

When adding/removing `@cocotb.test` entries in Python test files, sync the BUILD file:
```bash
python3 utils/update_cocotb_tests.py <test.py> <BUILD> <VARIABLE_NAME> <target_name>
# Or update all at once:
python3 utils/update_all_cocotb_tests.py
```

Testcase lists in BUILD files are delimited by `# BEGIN_TESTCASES_FOR_<name>` / `# END_TESTCASES_FOR_<name>` markers.

## Architecture

### RTL Layer (Chisel → SystemVerilog)

The Chisel source is in `hdl/chisel/src/` and compiled to SystemVerilog by `chisel_cc_library` Bazel rules.

**Scalar pipeline** (`hdl/chisel/src/coralnpu/scalar/`): Three-stage, in-order, 4-wide dispatch.
- `Fetch.scala` — Instruction fetch (128-bit bus, optional L0 cache)
- `Decode.scala` — Decodes up to 4 instructions; scoreboard manages RAW/WAW hazards
- `Alu.scala`, `Bru.scala`, `Mlu.scala`, `Dvu.scala` — Execution units (1 ALU/lane, 1 shared MLU, 1 DVU)
- `Lsu.scala` — Load/Store Unit; uses slot-based state machine per transaction
- `Fpu.scala`, `FRegfile.scala` — Scalar floating-point

**Vector extension** (`hdl/chisel/src/coralnpu/rvv/`): Wraps the RVV Verilog backend.
- `RvvCore.scala` — Chisel wrapper for the hand-written `hdl/verilog/rvv/` RTL
- `RvvDecode.scala` — Vector instruction decode
- `RvvInterface.scala` — Scalar↔vector interface bundles

**Bus infrastructure** (`hdl/chisel/src/bus/`):
- `TileLinkUL.scala`, `TlulSocket1N.scala`, `TlulSocketM1.scala` — Internal TileLink-UL fabric
- `Axi.scala`, `Axi2TLUL.scala`, `TLUL2Axi.scala` — AXI4 ↔ TLUL bridges
- `DmaEngine.scala` — DMA engine

**Top-level wrappers** (`hdl/chisel/src/coralnpu/`):
- `Core.scala` — Connects scalar + RVV + FPU + caches + TCM
- `CoreAxi.scala` / `CoreTlul.scala` — Adds AXI or TLUL external interface
- `Fabric.scala` — Internal address decode and bus routing
- `Parameters.scala` — All RTL configuration knobs

### RTL Variants

Variants are produced by `chisel_cc_library` with different `gen_flags`:

| Bazel target suffix | Module name | Notes |
|---|---|---|
| `core_mini_axi_cc_library` | `CoreMiniAxi` | Scalar+float, 8KB ITCM/32KB DTCM |
| `rvv_core_mini_axi_cc_library` | `RvvCoreMiniAxi` | + RVV (`--enableRvv=True`) |
| `rvv_core_mini_highmem_axi_cc_library` | `RvvCoreMiniHighmemAxi` | 1MB ITCM+DTCM |
| `rvv_core_mini_itcm512kb_dtcm512kb_axi_cc_library` | `RvvCoreMini_ITCM512KB_DTCM512KBAxi` | 512KB ITCM+DTCM |
| `*_verification_*` | `*Verification*` | `--enableVerification=True` adds RVVI trace |

### Default Memory Map

| Address | Region |
|---|---|
| `0x0000000` | ITCM (8 KB by default) |
| `0x0010000` | DTCM (32 KB by default) |
| `0x0030000` | CSR/Peripheral |

The `highmem` layout shifts DTCM to `0x00100000` and CSR to `0x00200000` to support variable TCM sizes up to 1 MB.

### Simulation Layer

- **cocotb tests** (`tests/cocotb/`) — Python test modules driven by `cocotb_test_suite` / `verilator_cocotb_model` Bazel rules. The Verilator model is precompiled as a shared library; test runners load it via the cocotb Python API.
- **Test utilities** (`coralnpu_test_utils/`) — Shared Python helpers: `sim_test_fixture.py` (fixture base class), `core_mini_axi_interface.py` (AXI driver), `backdoor.py` (SRAM backdoor loading), `rvv_type_util.py` (RVV vector type helpers).
- **Verilator sim** (`tests/verilator_sim/`) — C++ testbench for stand-alone binary execution.
- **VCS sim** (`tests/vcs_sim/`) — C++ testbench, used with `--config=vcs`.
- **sram_backdoor** (`hdl/verilog/sram_backdoor.cc`) — DPI C++ code for direct SRAM access from simulation.

### Software Stack

- SW programs are built with `coralnpu_v2_binary` (in `rules/coralnpu_v2.bzl`), which applies a Bazel platform transition to the RISC-V toolchain (`//platforms:coralnpu_v2`).
- Toolchain is in `toolchain/` (clang-based cross-compiler wrappers).
- The CRT (`toolchain/crt/`) provides startup code and HTIF semihosting gloss.
- TFLite Micro is available under `sw/opt/litert-micro/`.

## Bazelrc Configs

| Flag | Purpose |
|---|---|
| *(default)* | Excludes VCS, synthesis, power targets |
| `--config=vcs` | Enables VCS simulator targets |
| `--config=synthesis` | Enables synthesis targets |
| `--config=power` | Enables power analysis targets |
| `--config=coralnpu_v2` | Builds for RISC-V target platform |
| `--config=opt` | Strips TFLite error strings |

User-local overrides go in `.bazelrc.user` (gitignored).

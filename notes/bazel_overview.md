# Bazel Build System

Bazel is a build system developed by Google (open-sourced in 2015). It's designed for large, multi-language codebases where correctness and speed matter.

## Core Ideas

**Hermetic builds** — each build action declares exactly what inputs it reads and what outputs it produces. Bazel enforces this, so builds don't silently depend on your local environment.

**Incremental / cached** — Bazel hashes inputs and skips any action whose inputs haven't changed. This makes repeated builds fast. The cache can also be shared across a team (remote caching).

**Parallel execution** — since every action's dependencies are explicit, Bazel can run independent actions in parallel safely.

**Multi-language** — one tool handles C++, Python, Java, Scala (via rules_scala), Go, etc. This repo uses it for Chisel/Scala RTL, C++ simulators, Python tests, and RISC-V cross-compilation all in one graph.

## Key Concepts

| Term | What it is |
|---|---|
| `BUILD` file | Declares targets (libraries, binaries, tests) in a package |
| `WORKSPACE` | Root config at `WORKSPACE`; declares external dependencies |
| Target (`//path:name`) | A named build unit (e.g. `//tests/cocotb:core_mini_axi_sim_cocotb`) |
| Rule | A function that defines how to build a target type (e.g. `cc_binary`, `py_test`) |
| `.bazelrc` | Default flag configuration |

## Rule vs Target

A **rule** is the *template* — it defines what attributes are accepted and how to build something. Declared once in a `.bzl` file.

A **target** is a *specific instance* of a rule — declared in a `BUILD` file with concrete values for those attributes.

### Example from this repo

The rule `verilator_cocotb_model` is defined in `rules/coco_tb.bzl`:

```python
verilator_cocotb_model = rule(
    implementation = _verilator_cocotb_model_impl,
    attrs = {
        "verilog_source": attr.label(...),
        "hdl_toplevel":   attr.string(...),
        "cflags":         attr.string_list(),
        "deps":           attr.label_list(),
    },
)
```

This is just a schema + a build function. It doesn't build anything on its own.

The targets are the concrete instances in `tests/cocotb/BUILD`:

```python
verilator_cocotb_model(
    name = "core_mini_axi_model",
    hdl_toplevel = "CoreMiniAxi",
    verilog_source = "//hdl/chisel/src/coralnpu:CoreMiniAxi.sv",
    cflags = VERILATOR_BUILD_ARGS,
    deps = ["//hdl/verilog:sram_backdoor"],
)

verilator_cocotb_model(
    name = "rvv_core_mini_axi_model",
    hdl_toplevel = "RvvCoreMiniAxi",
    verilog_source = "//hdl/chisel/src/coralnpu:RvvCoreMiniAxi.sv",
    ...
)
```

Each call creates a separate target with its own name, inputs, and outputs. The rule's implementation runs once per target when that target is built.

## Bazelrc Configs

Defined in `.bazelrc` at the repo root:

| Flag | Purpose |
|---|---|
| *(default)* | Excludes VCS, synthesis, power targets |
| `--config=vcs` | Enables VCS simulator targets (requires VCS license) |
| `--config=synthesis` | Enables synthesis targets |
| `--config=power` | Enables power analysis targets |
| `--config=coralnpu_v2` | Builds for RISC-V target platform (`//platforms:coralnpu_v2`) |
| `--config=opt` | Strips TFLite error strings |

User-local overrides go in `.bazelrc.user` (gitignored).

## Custom Rules in This Repo

All custom Bazel rules live in `rules/`:

| Rule file | Key rules | Purpose |
|---|---|---|
| `rules/chisel.bzl` | `chisel_cc_library` | Compiles Chisel (Scala) to SystemVerilog via firtool |
| `rules/coco_tb.bzl` | `verilator_cocotb_model`, `cocotb_test_suite` | Precompiles Verilator models and generates per-testcase targets |
| `rules/coralnpu_v2.bzl` | `coralnpu_v2_binary` | Cross-compiles C/C++ to RISC-V ELF with platform transition |
| `rules/vcs.bzl` | VCS rules | VCS simulation model compilation |
| `rules/mpact.bzl` | `mpact_binary` | Builds the MPACT ISS with host clang transition |
| `rules/lint.bzl` | Lint rules | Verilog linting (VCS-based) |

## Why This Repo Uses It

This project mixes Chisel (Scala), C++ (Verilator/VCS testbenches), Python (cocotb), and RISC-V cross-compilation. Bazel handles all of them in one dependency graph, enforces reproducibility, and makes it practical to cache the expensive Verilator pre-compilation step across runs.

## Common Commands

```bash
# Build a RISC-V binary
bazel build //examples:coralnpu_v2_hello_world_add_floats

# Build the Verilator simulator
bazel build //tests/verilator_sim:core_mini_axi_sim

# Run the main cocotb test suite
bazel run //tests/cocotb:core_mini_axi_sim_cocotb

# Run a single cocotb testcase
bazel test //tests/cocotb:core_mini_axi_sim_cocotb_core_mini_axi_basic_write_read_memory_verilator

# Emit Verilog from Chisel
bazel build //hdl/chisel/src/coralnpu:core_mini_axi_cc_library_verilog

# Run Chisel unit tests
bazel test //hdl/chisel/src/coralnpu:coralnpu_scalar_tests
```

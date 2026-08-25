# `//platforms/` Package

The `//platforms/` package defines Bazel platform configurations for the CoralNPU V2 core. Its sole purpose is distinguishing **bare-metal** builds from **semihosting** builds.

## Structure

```
platforms/
├── BUILD.bazel      # Platform definitions + config_setting
├── cpu/
│   └── BUILD        # Custom constraint_setting: cpu → coralnpu_v2
└── os/
    └── BUILD        # Custom constraint_setting: os → semihosting
```

## Custom Constraints

### CPU (`//platforms/cpu:coralnpu_v2`)

A single constraint value representing the CoralNPU V2 RISC-V core. Both platforms share this — there is no separate constraint for scalar vs. vector cores. That distinction is an RTL-level choice (`gen_flags` passed to Chisel), not a toolchain one.

### OS (`//platforms/os:semihosting`)

Indicates that the binary should be linked with HTIF (Host-Target Interface) semihosting support. This is a **simulation/debugging mechanism**, not a production multi-core configuration.

With semihosting, the core traps certain instructions and the **simulator** (Verilator/VCS on the host workstation) handles them — e.g. `printf()` output appears in your terminal without needing a UART or any real peripheral. It exists purely for development convenience: writing test programs that can print results, read files, etc.

In a real deployment, the core runs bare-metal (`os:none`) and communicates with a host processor through actual hardware interfaces (AXI bus, DMA, memory-mapped registers), not simulator traps.

## Platforms

| Platform | OS Constraint | Effect |
|---|---|---|
| `coralnpu_v2` | `@platforms//os:none` | Bare-metal. Links with `nano.specs`, default CRT. |
| `coralnpu_v2_semihosting` | `//platforms/os:semihosting` | Links with `htif_nano.specs`, `-lsemihost`, and `crt_semihosting`. |

Both platforms use the same CPU constraint and resolve to the same clang-based RISC-V cross-compiler toolchain.

## How It Gets Used

The `coralnpu_v2_binary` macro (in `rules/coralnpu_v2.bzl`) uses a Starlark transition to set `--platforms` to one of these two platforms based on the `semihosting` attribute. This triggers Bazel's toolchain resolution to pick the RISC-V toolchain registered in `//toolchain/`.

The platform choice affects two things downstream:

1. **Linker specs** — `cc_toolchain_config.bzl` checks `ctx.attr.semihosting` to select either `nano.specs` or `htif_nano.specs` + `-lsemihost`.
2. **CRT** — `coralnpu_v2_binary` appends either `//toolchain/crt` (bare-metal) or `//toolchain/crt:crt_semihosting`.

## `coralnpu_config` Config Setting

A `config_setting` matching the bare-metal platform (`coralnpu_v2` CPU + `os:none`). Used in `select()` expressions elsewhere in the repo to conditionally include sources or flags when building for CoralNPU.

## What This Package Does NOT Handle

- **Scalar vs. vector core** — determined by RTL `gen_flags` (e.g. `--enableRvv=True`), not the SW platform. The compiler always targets `rv32imf_zve32f_...` so all binaries *can* use vector instructions.
- **Memory sizes (ITCM/DTCM)** — configured via linker script parameters in `coralnpu_v2_binary`.
- **Verification hooks** — controlled by `--enableVerification=True` in RTL build targets.

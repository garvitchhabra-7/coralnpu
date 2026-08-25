# `//toolchain/` Package

The `//toolchain/` package provides the clang-based RISC-V cross-compiler toolchain, C runtime, and linker script template for building CoralNPU V2 binaries.

## Structure

```
toolchain/
├── BUILD.bazel                  # Toolchain registration (two variants)
├── cc_toolchain_config.bzl      # Compiler/linker flag definitions
├── coralnpu_tcm.ld.tpl          # Linker script template (memory map)
├── crt/                         # C runtime (bare-metal + semihosting)
│   ├── BUILD
│   ├── crt.S                    # Low-level section clear/copy utilities
│   ├── coralnpu_start.S         # Entry point (_start)
│   ├── coralnpu_gloss.cc        # Bare-metal syscall stubs (no-op I/O)
│   ├── coralnpu_htif_gloss.cc   # Semihosting syscall stubs (HTIF to simulator)
│   ├── coralnpu_exceptions.cc   # Default exception handler
│   └── cxx_guards.cc            # C++ static init guards
├── wrappers/                    # Shell scripts resolving cross-compiler binaries
│   ├── driver.sh                # Main wrapper (strips -lpthread, finds toolchain)
│   ├── gcc, clang, ld, ar, ...  # Symlinks/scripts for each tool
│   └── gdb
├── host_clang/                  # Host-native clang wrappers (for exec-config tools)
└── build_scripts/               # Scripts to build the toolchain itself
```

## Toolchain Config (`cc_toolchain_config.bzl`)

Defines all compiler and linker flags. Key decisions:

- **Architecture**: `-march=rv32imf_zve32f_zicsr_zifencei_zbb_zfbfmin_zvfbfmin_zvfbfwma` — always includes vector and BFloat16 extensions. There is no separate scalar-only toolchain; the compiler can always emit vector instructions regardless of which RTL core the binary will run on.
- **ABI**: `-mabi=ilp32` (or `lp64` when `is_rv64=True`)
- **Code model**: `-mcmodel=medany`, `-nostdlib`
- **Linker specs**: Selects between `nano.specs` (bare-metal) and `htif_nano.specs` + `-lsemihost` (semihosting) based on the `semihosting` attribute.
- **Other flags**: `-Wall -Werror`, `-fno-rtti`, `-fno-exceptions`, `-Wl,--gc-sections`, linker map generation.

## Wrappers (`wrappers/`)

Shell scripts that locate the actual `riscv64-unknown-elf-*` binaries from the external `@toolchain_coralnpu_v2` repository. `driver.sh` also filters out `-lpthread`/`-pthread` flags that abseil and tflite_micro inject, since bare-metal newlib has no pthreads.

## C Runtime (`crt/`)

Two variants, both using `alwayslink = True` so they're always linked in:

| Target | Gloss file | Behavior |
|---|---|---|
| `crt` (bare-metal) | `coralnpu_gloss.cc` | Stub syscalls — `_write` buffers to a line buffer that goes nowhere, `_exit` is just `ebreak`. Compiled with `-DSKIP_HTIF_SYMBOLS`. |
| `crt_semihosting` | `coralnpu_htif_gloss.cc` | Real HTIF syscalls — `_write`/`_read`/`_open`/`_close` go through `tohost`/`fromhost` mailbox to the simulator, `_exit` encodes exit status in `tohost`. |

### Shared startup (`coralnpu_start.S`)

The `_start` entry point is shared by both variants. It does:

1. Zeroes all scalar registers to a known state
2. Sets up stack pointer (`sp`) and global pointer (`gp`)
3. Clears `.bss` section
4. Runs C++ constructors (`.init_array`)
5. Installs default trap vector
6. Sets FP and vector state to Dirty in `mstatus` (bits `0x6600`)
7. Writes sentinel `0x0badd00d` to `_ret` (to detect non-clean exits)
8. Calls `main(0, 0)`
9. Runs C++ destructors (`.fini_array`)
10. Stores return value in `_ret`, then `mpause` on success or `ebreak` on failure

### Low-level utilities (`crt.S`)

Provides `crt_section_clear` and `crt_section_copy` — word-aligned memory operations used before the C runtime is initialized. These don't need a valid stack pointer.

## Linker Script Template (`coralnpu_tcm.ld.tpl`)

Defines the memory map with template placeholders filled in by `generate_linker_script`:

| Region | Address | Contents |
|---|---|---|
| ITCM | `0x00000000` | `.text`, `.rodata`, `.init.array`, `.fini.array` |
| DTCM | Configurable | `.data`, `.bss`, `.htif`, `.heap`, `.stack` |
| EXTMEM | `0x20000000` | `.extdata`, `.extbss` (extended memory sections) |
| DDR | `0x80000000` | `.ddr_data`, `.ddr_bss` (model weights, large data) |

ITCM/DTCM sizes, stack size, heap size/location are all parameterized. The `coralnpu_v2_binary` macro in `rules/coralnpu_v2.bzl` generates the linker script at build time with the requested values.

## Toolchain Registration (`BUILD.bazel`)

Registers two `cc_toolchain` + `toolchain` pairs, matched by platform constraints from `//platforms/`:

| Bazel toolchain | Platform match | Config |
|---|---|---|
| `cc_coralnpu_v2_toolchain` | `cpu:coralnpu_v2` + `os:none` | `nano.specs`, default CRT |
| `cc_coralnpu_v2_semihosting_toolchain` | `cpu:coralnpu_v2` + `os:semihosting` | `htif_nano.specs` + `-lsemihost`, semihosting CRT |

Both execute on `x86_64 linux` (the host workstation) and target `coralnpu_v2` (the RISC-V core).

Also generates two pre-built linker scripts for common configurations:
- `coralnpu_tcm.ld` — default 8KB ITCM / 32KB DTCM
- `coralnpu_tcm_highmem.ld` — 1MB ITCM / 1MB DTCM

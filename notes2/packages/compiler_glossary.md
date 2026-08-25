# Compiler Glossary

Quick reference for compiler/toolchain terms used in the CoralNPU build system.

## Core Concepts

**Toolchain**: The set of programs that turn source code into a runnable binary — compiler, assembler, linker, and utilities like `objcopy`. A *cross-compiler* toolchain runs on one architecture (x86_64 Linux) but produces binaries for another (RISC-V).

**ABI (Application Binary Interface)**: The contract for how compiled code passes data around at the machine level — which registers hold function arguments, how the stack is laid out, how large `int`/`long`/pointers are. `ilp32` means int/long/pointer are all 32-bit; `lp64` means long/pointer are 64-bit. If two object files use different ABIs they can't be linked together.

**Linker**: Takes compiled object files (`.o`) and libraries (`.a`) and combines them into a single executable. It resolves symbol references (e.g. when `main.o` calls a function defined in `utils.o`) and assigns final memory addresses.

**Linker Script**: Tells the linker *where* to place code and data in memory. Critical for bare-metal targets where there's no OS to handle memory layout. For CoralNPU, it maps `.text` into ITCM, `.data` into DTCM, etc.

**CRT (C Runtime)**: Startup code that runs before `main()`. It sets up the stack, zeroes `.bss`, runs C++ constructors, and after `main()` returns, runs destructors and halts. On bare-metal there's no OS to do this, so the CRT handles it.

## Compiler Flags

**`-march`** (Machine Architecture): Specifies which ISA extensions the compiler can use. `rv32imf_zve32f` means 32-bit RISC-V with integer multiply, float, and vector extensions. The compiler will emit instructions from these extensions.

**`-mabi`** (Machine ABI): Specifies the calling convention (see ABI above). Must match the libraries you link against.

**`-mcmodel`** (Code Model): Controls how the compiler generates addresses. `medany` means code/data can be anywhere in a 2GB window — flexible enough for most bare-metal layouts without paying the cost of full 32-bit address materialization on every access.

**`-nostdlib`**: Don't automatically link the standard C library startup code. Used when you provide your own CRT (as CoralNPU does).

**`-nostdinc`**: Don't search default system include paths. Used with `-isystem` to point at the cross-toolchain's headers instead of the host system's.

**`--specs=nano.specs`**: Use the "nano" variant of newlib — a minimal C library optimized for code size on embedded targets. `htif_nano.specs` adds HTIF semihosting support on top.

## Linker Flags

**`-Wl,-T,<script>`**: Pass a linker script to the linker via the compiler driver. `-Wl,` means "forward this flag to the linker".

**`-Wl,--gc-sections`**: Garbage-collect unused sections. Combined with `-ffunction-sections` and `-fdata-sections` (which put each function/variable in its own section), this strips dead code from the final binary — important when ITCM is only 8KB.

**`-Wl,--start-group` / `--end-group`**: Search the enclosed libraries repeatedly until no new symbols are resolved. Needed when libraries have circular dependencies (e.g. libc and libgcc).

**`-Wl,-Map`**: Emit a linker map file showing where every symbol ended up in memory. Useful for debugging memory layout issues.

## Binary Formats

**ELF (Executable and Linkable Format)**: Standard binary format containing code, data, symbol tables, and debug info. This is what the linker produces and what debuggers/simulators consume.

**BIN (Raw Binary)**: Just the raw bytes to load into memory, no metadata. Produced by `objcopy -O binary` from the ELF. Used for direct memory loading.

**VMEM (Verilog Memory)**: A hex text format that Verilog's `$readmemh` can read. Produced by `srec_cat` from the BIN. Used to preload simulation memory (ITCM/DTCM) in Verilator/VCS.

## Newlib / Gloss

**Newlib**: A lightweight C standard library designed for embedded systems. Provides `printf`, `malloc`, `string.h`, etc. The "nano" variant is further stripped down for minimal code size.

**Gloss (libgloss)**: The OS abstraction layer that newlib calls into for syscalls (`_read`, `_write`, `_sbrk`, `_exit`, etc.). On bare-metal, these are stubbed out (return errors or no-op). With semihosting, they forward to the host via HTIF.

**HTIF (Host-Target Interface)**: A mailbox protocol between the RISC-V core and the simulator. The core writes a syscall request to a `tohost` memory location, the simulator executes it on the host OS, and writes the result to `fromhost`.

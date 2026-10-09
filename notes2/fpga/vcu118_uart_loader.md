# VCU118 — ROM UART Loader

Written 2026-10-07. Decision (user, 2026-10-07): load programs and data over the existing USB-UART,
instead of an FTDI/SPI adapter or JTAG-to-AXI (`vcu118_image_test_plan.md`).

Working rules as in `vcu118_uart_ila_debug.md`: the user runs Bazel, Vivado and the board.

## Status

| Step | State |
|---|---|
| Loader, test program, host script, BUILD targets written | done |
| Host script vs. a Python model of the protocol (pty, injected CRC error) | passes |
| RISC-V build of the loader / test program | done: loader 4.4 KB of the 32 KB ROM, RAM at `0x001F0000`; hello 2.3 KB ITCM + 32 B DTCM, entry `0x0` |
| Sim testbench: UART RX was not connected (see below) | fixed in `fpga/rtl/chip_verilator.sv` |
| Verilator ROM sim with the host script on the uartdpi pty | **passed** 2026-10-07: PING, ITCM write by DMA + read-back CRC `0x88f33ee2`, DTCM write + CRC `0x72072871`, GO, `uart_loader_hello PASS`. Sim start 14:35:51 to PASS 15:10:49 (~35 min) |
| Bitstream `fpga/bitstreams/vcu118_highmem_rom_2026-10-07_183310/` (loader ROM + group A XDC) | built; ROM `.vmem` md5 `095f8a69…` = sim-tested loader |
| Board, 2026-10-09 | **passed**: (1) `uart_loader_hello` load + CRCs + `PASS` at 35 MHz; (2) 256 KB random data → DDR `0x80100000`, read-back CRC ok, 23.1 s (11.1 KB/s); (3) CPU_RESET → reload → `PASS` again |

## Files

| File | What |
|---|---|
| `fpga/sw/rom_uart_loader.c` | ROM program (target `//fpga:rom_uart_loader_highmem`, vmem `..._vmem`) |
| `fpga/sw/rom_boot/rom_loader_highmem.ld` | Like `rom_highmem.ld`, but the loader's RAM is `0x001F0000`–`0x001FFFFF` |
| `fpga/sw/uart_loader_hello.c` | First program to load (`//fpga:uart_loader_hello`, 1 MB/1 MB TCM) |
| `fpga/uart_loader.py` | Host side, stdlib only (runs with the RHEL8 `/usr/bin/python3` 3.6). Docstring has the protocol |
| `fpga/BUILD` | `_VCU118_ROM_VMEM["highmem"]` now points to the loader, so every `*_highmem_rom` VCU118 build bakes it in |
| `fpga/rtl/chip_verilator.sv` | Sim only: the uartdpi models now drive the SoC's UART RX inputs |

## How it works

- Autoboot starts the loader from ROM. It prints a banner on UART1, then waits for binary request
  frames: PING, BAUD, WRITE (≤ 4 KB, CRC-checked), CRC (read-back check), GO.
- **ITCM is written by DMA.** The LSU raises a fault on any store to ITCM
  (`hdl/chisel/src/coralnpu/scalar/Lsu.scala`, `ibusFault`), so each ITCM chunk lands in a DTCM
  buffer and the DMA engine copies it over `coralnpu_device`, the same route the Nexus flash
  bootloader (`rom_boot/main.c`) uses. DTCM, SRAM and DDR are written with plain stores.
- **The loader keeps its RAM in the top 64 KB of DTCM.** Programs linked with
  `coralnpu_tcm.ld.tpl` put `.data` at the bottom of DTCM, and their stack and `.bss` aren't
  loaded, so they don't collide with it. The loader and the host script both refuse writes there.
- **DDR writes are refused until calibration is done** (`gpio_i[0]`). PING reports the calibration
  state.
- **Transfers run at 115200 baud** (user decision, 2026-10-07: known to work). That is about
  11 KB/s, so a 300 KB model takes about 30 s. The loader still has a BAUD command, and
  `--baud 921600` would try it, but it's untested; the loader falls back to 115200 after 3 s
  without a valid frame.
- **Every region gets a read-back CRC** computed by the core after loading. This catches DDR
  corruption from the unmet 300 MHz MIG-side timing (group B in `vcu118_timing_fixes.md`).
- **Getting back to the loader:** a program that finishes halts the core (crt `ebreak`/`mpause`).
  Press **CPU_RESET**, which re-runs autoboot, and the loader comes back.

## Open risks (check in sim, then on the board)

1. **CRC of ITCM uses CPU loads.** These should work: the LSU's ITCM loads share the fetch port
   (`scalar/SCore.scala:563`). If the read-back check traps anyway (the loader prints
   `LOADER TRAP`), DMA ITCM back into the DTCM buffer before computing the CRC.
2. **Loader speed.** It runs from ROM over the bus; its per-byte loop must stay under about
   3000 cycles per byte at 115200, which should be easy.
3. **DMA on VCU118.** The DMA engine has never been used on this board. It works in the VCU118
   highmem sim (2026-10-07 run above).

Risk 1 is also cleared by the sim run: the ITCM read-back CRC matched.

## Sim findings (2026-10-07)

- **The Verilator top never connected UART RX.** `chip_verilator.sv` wired each uartdpi's `tx_o`
  to a local `uartN_rx` that went nowhere, and fed the SoC's `uart_sideband_i` from an undriven
  top-level port. The loader's banner came out, but the host's ping never arrived. Fixed by
  driving `uart_sideband_i[n].cio_rx` from `uartN_rx`, as `chip_vcu118.sv` / `chip_nexus.sv` do,
  and dropping the port (nothing else used it). The VCU118 RTL already wires `uart_rx_i[1]` (AW25)
  correctly (`chip_vcu118.sv:144`), so bitstreams are unaffected.
- **The sim is slow: a few thousand cycles per second.** Boot plus the 115-byte banner takes about
  2 minutes. The uartdpi runs at 115200 against the 50 MHz sim clock, so each byte costs about
  4,340 cycles, and loading `uart_loader_hello` (~2.4 KB) takes about 30–40 minutes. Use
  `--time-scale 10000`; at 1000 the host gives up on a chunk before the sim has received it.
- **Speeding up the sim UART was considered and dropped.** It would be at most ~27× faster (UART
  16× oversampling and 16-bit NCO limit it to ~3.1 Mbaud at 50 MHz). It would need a sim-only
  rate in the testbench, the loader, the test program and `uart.c`, and wouldn't tell us anything
  about the board, which runs at 115200.
- **`uart1.log` shows binary replies late.** The uartdpi log is flushed at newlines, so the loader's
  binary replies (`5a 00 00 00 <value>`) only appear when the next text line arrives. Read them
  with `tail -c +116 uart1.log | od -An -tx1`.
- **The host can start before the banner is done.** The ping waits in the pty and the UART's
  64-byte RX FIFO, and the loader picks it up after printing.

## Commands for the user

Inside FHS:
```bash
bazelisk build //fpga:rom_uart_loader_highmem_vmem //fpga:uart_loader_hello \
  //fpga:build_chip_verilator_highmem_rom
# RISC-V outputs are in the transitioned configuration, not bazel-bin/fpga. The hash can change
# with build flags; if it does: find -L bazel-out -name uart_loader_hello.elf
D=bazel-out/k8-fastbuild-ST-dd8dc713f32d/bin/fpga
# Sim: note the "/dev/pts/N" that uartdpi prints for uart1. Watch uart1.log for the banner.
bazel-bin/fpga/build.build_chip_verilator_highmem_rom/com.google.coralnpu_fpga_chip_verilator_0.1/sim-verilator/Vchip_verilator \
  +UARTDPI_LOG_uart1=uart1.log --meminit=rom,$PWD/$D/rom_uart_loader_highmem.vmem
# Second terminal (the sim is far slower than real time, hence --time-scale):
python3 fpga/uart_loader.py --port /dev/pts/N --time-scale 10000 \
  --elf $D/uart_loader_hello.elf --expect "uart_loader_hello PASS" --monitor 36000 -v
```
Run only one sim instance. In the sim, PING reports `DDR NOT calibrated`; that's expected and
doesn't matter for TCM loads.

Then, outside FHS (`bazelisk shutdown` first):
```bash
df -h /
bazelisk build //fpga:build_chip_vcu118_elab_only_highmem_rom
bazelisk run //fpga:archive_chip_vcu118_bitstream_highmem_rom
```
On the board: open `ttyUSB4` first to see the banner (optional), close it, then run
`python3 fpga/uart_loader.py --elf $D/uart_loader_hello.elf` with the default `--port /dev/ttyUSB4`.
After the program halts, press CPU_RESET before loading again.

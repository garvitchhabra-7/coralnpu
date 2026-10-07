# VCU118 — Task 7.2 (UART verification): How It Was Done

Written 2026-10-06. Task 7.2 of `vcu118_porting_plan.md`.

## Result

The original task asked only that the USB-UART port enumerate. It went further than that: the
core boots on its own from ROM and prints on the board UART. Bitstream:
`fpga/bitstreams/vcu118_highmem_rom_2026-10-05/` (`chip_vcu118.bit`, md5 `533785de…`).

`/dev/ttyUSB4`, 115200 8N1:

```
CoralNPU ROM boot OK
main clk MHz: 0x00000028
alive 0x00000000
alive 0x00000001      (once per second)
```

`0x28` = 40 MHz, the `clk_main` frequency of that build.

## Why it needed a ROM-boot bitstream

The 7.1 bitstream (`fpga/bitstreams/vcu118_highmem_2026-09-25/`,
`//fpga:build_chip_vcu118_bitstream_highmem`) boots from ITCM. After programming, ITCM is empty
and the core idles, so the UART stays silent.
- That bitstream has two load paths: the SPI slave (FTDI MPSSE adapter on PMOD1 + `nexus_loader`)
  or RISC-V JTAG (adapter on PMOD0). Neither adapter is available (this is why 7.3 is skipped).
- The existing `_rom` flow (`rom_test_highmem`) is a bootloader that copies the program from SPI
  flash. No SPI flash is wired to the SoC on VCU118, so it can't work here.

The solution was a program that runs **directly from ROM** and is baked into the bitstream at
build time, so the board prints on power-up with no extra cable.

## What was built

| Piece | Where | What it does |
|---|---|---|
| ROM program | `fpga/sw/rom_hello_test.c` (commit `8e504972`) | `uart_init()`, banner, clock-table frequency, then `alive N` once per second forever. Must never return: `crt0` has no exit path |
| Startup code | `fpga/sw/rom_boot/crt0.S` | Sets `sp`, copies `.data` from ROM to DTCM, zeroes `.bss`, tail-calls `main` |
| Linker script | `fpga/sw/rom_boot/rom_highmem.ld` | Code and rodata in ROM `0x10000000` (32 KB); data, bss and the 1 KB stack in DTCM `0x00100000` |
| Bazel target | `//fpga:rom_hello_highmem` and `rom_hello_highmem_vmem` | Builds the ELF and its `.vmem` image |
| ROM image selection | `_VCU118_ROM_VMEM["highmem"]` in `fpga/BUILD` | Picks the `.vmem` that the VCU118 `_rom` targets bake in |
| Bitstream target | `//fpga:build_chip_vcu118_bitstream_highmem_rom` | Passes `--EnableAutoboot=1`, `--MemInitFile=<vmem>` and `--BootAddr=268435456` (`0x10000000`) |

### How the core gets from reset to `main`

1. The ROM (`prim_rom_adv` in `coralnpu_soc.sv`) is initialised from `MemInitFile` at synthesis.
   With only ~400 non-zero words, Vivado implements it as LUTs, not BRAM. This is normal (see
   `vcu118_uart_ila_debug.md`).
2. `EnableAutoboot=1` instantiates `fpga/rtl/autoboot.sv`. After reset, this FSM writes the core's
   control register over TL-UL (`CsrBaseAddr` = `0x00200000` for highmem):
   - first `0x1`, which releases the clock gate;
   - then `0x0`, which releases the core from reset.
3. The core starts at `BootAddr` = `0x10000000`, i.e. `_start` in ROM.

### UART path

- **SoC side:** the console is **UART1** at `0x40010000` (`fpga/sw/uart.c`).
- **Pins** (`fpga/pins_vcu118.xdc:94-108`), all LVCMOS18:
  - `uart_tx_o[1]` → BB21 (`USB_UART_TX`), `uart_rx_i[1]` ← AW25 (`USB_UART_RX`), both on the
    CP2105;
  - UART0 has no second channel on the bridge, so it is parked on the CTS/RTS pins (BB22/AY25).
- **Baud rate:** `uart_init()` reads the clock frequency from the clock table (`0x40001000`, set by
  the `ClockFrequencyMhz` build parameter) and computes the NCO from it. The baud rate therefore
  stays at 115200 when `clk_main` changes (50 → 40 → 35 MHz). No software edit is needed.
- **Host side:** plug in the micro-USB marked *USB UART* (not the JTAG one). On `synthesia` the
  console appears as `/dev/ttyUSB4`; the host is shared, so the number may change after re-plugging.
  Open the terminal **before** programming, because the banner prints only once:
  `screen /dev/ttyUSB4 115200`.

## Bugs that had to be fixed first

The UART only worked after three fixes. All three are in the tree now.

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | Only LED0 lit; the MIG debug registers all read 0 | `CPU_RESET` on VCU118 is **active-high**, but the design treated it as active-low (copied from Nexus), so the SoC and MIG stayed in reset | Invert the reset at the pad in `chip_vcu118.sv`, add a pull-down in the XDC (2026-09-25 rebuild). See `vcu118_progress.md`, Phase 6e |
| 2 | Pressing a push button upset the SPI flash outputs | `spim_flash_csb_o` / `spim_flash_rst_no` were on push-button pins | Moved to unused LED pins AU37/AV36 (XDC only) |
| 3 | ROM build (2026-09-29) silent: no UART, LED0/LED1 off; Verilator ROM sim worked | `coralnpu_soc.sv` connected autoboot's reset to `rst_main_nqq` before declaring it. Vivado made an undriven implicit net (`Synth 8-3848`), held the FSM in reset and optimised it away, so the core was never released | Declare the reset synchroniser before `gen_autoboot` (commit `cbdf0364`). The Nexus build shared the bug |

Full debug history for #3, including the wrong conclusions to avoid repeating:
`vcu118_uart_ila_debug.md`.

## Tools made along the way

- `fpga/program_vcu118.tcl`: programs the board. It checks that the `.bit` targets `xcvu9p`,
  selects the cable by serial **`210308B76D4D`** (the host is shared), and finds the FPGA on the
  JTAG chain.
- `fpga/check_ddr_vcu118.tcl`: read-only DDR calibration and liveness check through the `.ltx`.
- `fpga/inspect_routed_dcp.tcl`: offline check of a routed checkpoint, no hardware needed. It
  reports what drives the autoboot reset, the ROM contents compared with the `.vmem`, and the
  UART1 TX path.
- **Verilator ROM sim**, a reference before spending a 3.5 h build. Run one instance only; one
  heartbeat takes 50 M cycles:
  ```bash
  bazel-bin/fpga/build.build_chip_verilator_highmem_rom/com.google.coralnpu_fpga_chip_verilator_0.1/sim-verilator/Vchip_verilator \
    +UARTDPI_LOG_uart1=uart1.log --meminit=rom,$PWD/<path>/rom_hello_highmem.vmem
  ```

## Reproducing

```bash
# Outside FHS, after: module load Vivado/2025.2
screen /dev/ttyUSB4 115200          # separate terminal, open first
vivado -mode batch -source fpga/program_vcu118.tcl \
  -tclargs fpga/bitstreams/vcu118_highmem_rom_2026-10-05/chip_vcu118.bit
```

**Note:** since 2026-10-06 the VCU118 highmem ROM image is `rom_ddr_test_highmem` (task 7.4),
which prints the same banner and heartbeat and adds the DDR test. To rebuild with only the hello
program, point `_VCU118_ROM_VMEM["highmem"]` back at `:rom_hello_highmem_vmem`.

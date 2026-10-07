# VCU118 — Image Tests (Phase 8): Handoff

Written 2026-10-07 for the agent picking this up.

**First read the "Working rules" section of `notes2/fpga/vcu118_uart_ila_debug.md`.** In short:
- Don't run Bazel or bitstream builds, Vivado, or touch the board without asking the user. Prepare
  the changes and give the user the commands.
- Verilator/RISC-V builds run inside the FHS shell; Vivado runs outside it. Run
  `bazelisk shutdown` when switching between the two.
- The host `synthesia` is shared. Always select the JTAG cable by serial **`210308B76D4D`**.
- Do the elab check (`bazelisk build //fpga:build_chip_vcu118_elab_only_highmem_rom`) before any
  3.5 h bitstream build.
- Build and archive bitstreams in one step with
  `bazelisk run //fpga:archive_chip_vcu118_bitstream_highmem_rom`, which copies the outputs to
  `fpga/bitstreams/vcu118_highmem_rom_<build time>/`.

---

## Where things stand

| | |
|---|---|
| Board bitstream | `fpga/bitstreams/vcu118_highmem_rom_2026-10-06_201108/` (ROM boot) |
| Working | ROM autoboot, UART1 on `/dev/ttyUSB4` (115200 8N1), DDR4: the ROM test prints `DDR PASS` |
| Core | `RvvCoreMiniHighmemAxi`, 1 MB ITCM @ `0x00000000`, 1 MB DTCM @ `0x00100000`, `clk_main` 35 MHz |
| Other memory | ROM 32 KB @ `0x10000000` (baked into the bitstream), SRAM 4 MB @ `0x20000000`, DDR4 2 GB @ `0x80000000` |
| DDR calibration status | `gpio_i[0]` (GPIO `DATA_IN` at `0x40030000`, bit 0). Poll it before touching DDR |
| Not available | SPI program loading (7.3, no FTDI adapter) and RISC-V JTAG (7.5, no adapter on PMOD0) |
| Timing | not met, deliberately deferred (`vcu118_timing_fixes.md`, section "Results of the 2026-10-06 build") |

Background: `vcu118_progress.md` (status table at the top), `vcu118_task7_2_uart.md` (how ROM boot
works), `vcu118_ddr_check.md`.

## The blocker: no way to get a model or images onto the board

The only program path is the 32 KB ROM, and its contents are fixed when the bitstream is built
(`_VCU118_ROM_VMEM` in `fpga/BUILD`, currently `rom_ddr_test_highmem`). A MobileNet run needs much
more than that:
- the TFLite Micro runtime;
- the model (`tests/cocotb/tutorial/tfmicro/models/mobilenet_v1_0.25_224_int8_dummy.tflite` is
  300 KB);
- the tensor arena;
- the images.

**The user has to choose one of the options below.** Present them, and don't start implementing
before the choice is made.

---

## Option 1 — FTDI MPSSE adapter + `nexus_loader` (recommended if an adapter can be had soon)

This is the path the porting plan intended (task 7.3).

**Hardware:**
- An FT232H breakout or C232HM-DDHSL-0 cable (~€20–30). An FT4232H module also works.
- Wire it onto PMOD1 (J52):

  | FTDI | Signal | PMOD1 | FPGA pin |
  |---|---|---|---|
  | ADBUS0 | `spi_clk_i` | PMOD1_0 | N28 |
  | ADBUS3 | `spi_csb_i` | PMOD1_1 | M30 |
  | ADBUS1 | `spi_mosi_i` | PMOD1_2 | N30 |
  | ADBUS2 | `spi_miso_o` | PMOD1_3 | P30 |

  - Connect a common ground.
  - Leave ADBUS7 unconnected.
  - Check the physical PMOD pin numbering against UG1224 before wiring. Only the FPGA-pin side of
    this table has been verified.

**What the SPI slave can reach:** `spi2tlul` can write the TCMs (`coralnpu_device`), the SRAM, and
**DDR directly** (`CrossbarConfig.scala`, `connections`). So the host can put the program in ITCM and
images in DDR, start the core, and read results back.

**Software work** (details in `vcu118_progress.md`, section "7.4 `nexus_loader`"):
1. Replace the hard-coded `kFtdiPid = 0x6011` (`sw/utils/nexus_loader/main.cc:68`) with a `--pid`
   flag. The FT232H is `0x6014`.
2. Add a `--spi_divisor` flag. The SPI clock is hard-coded to 30 MHz (`main.cc:392-400`), but the
   design constrains `spi_clk_i` for 12 MHz. Use ≤ 10 MHz.
3. Build it with a small Nix script outside Bazel (no `libftdi1` / `libusb` headers on the host, and
   Nix libraries must not be linked against RHEL8 glibc through Bazel).
4. Always pass `--highmem` (CSR base `0x200000`). Never use `--reset` on VCU118; use `--soft_reset`.

**Bitstream:**
- The current ROM-boot bitstream releases the core immediately into the ROM test, which ends in an
  endless heartbeat. For loading, use the ITCM-boot variant (`build_chip_vcu118_bitstream_highmem`,
  no autoboot): the core waits until `nexus_loader --start_core`.
- That variant was last built on 2026-09-25, before the 35 MHz, DDR-clock and 2 GB-segment changes.
  **Rebuild it**: `bazelisk run //fpga:archive_chip_vcu118_bitstream_highmem`.
- Alternatively, the ROM program could hand over to ITCM on a flag. Then the ROM bitstream could be
  kept, but that is more work.

**Pros:** no FPGA change other than the rebuild above. Fast loading, and every reload is quick.
This is the long-term workflow for the demo.

**Cons:** needs hardware and the three `nexus_loader` patches.

## Option 2 — JTAG-to-AXI master over the existing JTAG cable (no new hardware)

Add Xilinx's JTAG-to-AXI master IP to `ddr_system_bd` as a second SmartConnect input. Vivado's
Hardware Manager can then write into DDR over the JTAG cable already attached (through the debug hub
the MIG already uses).

**Block design changes** (in `~/workspace/test_project`, the same procedure as the 2026-10-06
SmartConnect changes; see `fpga/ip/ddr4_vcu118/GENERATING_DDR4_IP.md`):
```tcl
create_bd_cell -type ip -vlnv xilinx.com:ip:jtag_axi jtag_axi_0
set_property -dict [list CONFIG.PROTOCOL 0 CONFIG.M_AXI_DATA_WIDTH 32] [get_bd_cells jtag_axi_0]   ;# AXI4
set_property CONFIG.NUM_SI 2 [get_bd_cells smartconnect_0]
connect_bd_intf_net [get_bd_intf_pins jtag_axi_0/M_AXI] [get_bd_intf_pins smartconnect_0/S01_AXI]
connect_bd_net [get_bd_pins ddr4_0/addn_ui_clkout1] [get_bd_pins jtag_axi_0/aclk]    ;# 100 MHz, like S00
connect_bd_net [get_bd_ports c0_ddr4_aresetn_0] [get_bd_pins jtag_axi_0/aresetn]
assign_bd_address
set_property offset 0x80000000 [get_bd_addr_segs {jtag_axi_0/Data/SEG_ddr4_0_C0_DDR4_ADDRESS_BLOCK}]
set_property range 2G          [get_bd_addr_segs {jtag_axi_0/Data/SEG_ddr4_0_C0_DDR4_ADDRESS_BLOCK}]
validate_bd_design
```
- Treat these commands as a starting point, not tested commands: check the property names
  against the IP in Vivado 2025.2.
- Keep the S00 segment at 2 GB from `0x80000000`.
- Regenerate, then copy the new DCPs and `rtl/ddr_system_bd.v` into the repo. The jtag_axi IP gets
  its own OOC checkpoint, which `vivado_ddr4_vcu118_setup.tcl` and `ddr4_vcu118.core` must also
  load.
- The wrapper's ports should not change. Check this with the same port diff as before.

**ROM bootloader** (replaces `rom_ddr_test_highmem` as the ROM image, or extends it):
1. Banner, then wait for calibration on `gpio_i[0]`.
2. Poll a mailbox word in DDR, e.g. at `0x80000000`, until the host writes a magic value. The host
   writes it **last**, after the payload.
3. Read a header (payload address, length, entry point, CRC32), check the CRC, copy the program to
   ITCM/DTCM and jump to it. Print the CRC result on the UART.

**Verify before building on it:**
- Whether the core can write ITCM with stores. If not, the program has to run from DDR or be loaded
  differently.
- Whether it can fetch instructions from DDR. It does fetch from ROM over the bus, so DDR probably
  works, but slowly.

**Host side:**
- A Vivado Tcl script, modelled on `fpga/check_ddr_vcu118.tcl` (select cable `210308B76D4D`, load
  the `.ltx`), that uses `create_hw_axi_txn` / `run_hw_axi` to write a binary file in bursts.
- JTAG-to-AXI is slow, roughly 100 KB/s or less. A few-MB model and images take seconds to minutes,
  which is acceptable for tests.

**Pros:** works with what is on the desk, and needs no RTL change in the Chisel subsystem.

**Cons:**
- A block design change and IP regeneration, a new bootloader, a host script, and a 3.5 h rebuild.
- Every load goes through Vivado.
- The written data passes through the 300 MHz MIG side that doesn't meet timing (group B), so CRC
  every load.

## Option 3 — Everything in ROM (not recommended)

Enlarge the ROM and bake the program, model and images into the bitstream.
- This needs a crossbar change (the `rom` range is 32 KB in `CrossbarConfig.scala`) and megabytes
  of extra BRAM on a chip that is already congested (BRAM 71/62/84% per SLR).
- Every new image or model means a 3.5 h rebuild.
- Mention it only for completeness.

---

## Decisions to get from the user

1. **Option 1 or 2.** Option 1 if an FTDI adapter can arrive within a few days, otherwise option 2.
2. **Which model and input size.**
   - The existing asset is MobileNet v1 0.25 224 int8 (300 KB, "dummy" weights,
     `tests/cocotb/tutorial/tfmicro/models/`).
   - Real classification results need a model with trained weights and preprocessed images.
3. **How much on-chip SRAM the plan needs.**
   - The linker template puts `.extdata` in SRAM (`EXTMEM`, `0x20000000`, 4 MB;
     `toolchain/coralnpu_tcm.ld.tpl`). It also has a `DDR` region, and `coralnpu_v2_binary` can
     place the heap in `DTCM`, `EXTMEM` or `DDR`.
   - Shrinking the 4 MB SRAM is the planned fix for the remaining timing problems (group B in
     `vcu118_timing_fixes.md`). So whatever is decided here also decides that fix.

## Existing software to start from

- `tests/cocotb/tutorial/tfmicro/run_partial_mobilenet.cc` and its BUILD targets
  (`run_mobilenet_v1_025_partial_binary`): a TFLite Micro MobileNet run, with the tensor arena in
  `.extdata`. It was written for the simulator, not the FPGA.
- `sw/utils/tflite_runner/`: a generic runner using the optimised `sw/opt/litert-micro` kernels.
- `fpga/sw/uart.h`, `clk.h`, `gpio.h`: UART1 console, clock table and GPIO (DDR calibration bit).
- `fpga/sw/rom_ddr_test.c`: an example of a ROM program with a trap handler, a calibration wait and
  UART reporting.

## Risks to keep in mind

- **Timing is not met** (`vcu118_timing_fixes.md`).
  - Group A (clock-domain crossings at 35 MHz) is almost certainly harmless.
  - Group B (the 300 MHz MIG side) is on the DDR data path. Put a CRC on everything loaded into
    DDR. If inference results look wrong, rerun the ROM DDR test before debugging the model.
- **Don't touch `0x80000000` before calibration:** an early access hangs the crossbar. Poll
  `gpio_i[0]`.
- **Open the UART before programming the FPGA:** the banner prints only once.

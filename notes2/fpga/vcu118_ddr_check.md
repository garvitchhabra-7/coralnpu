# VCU118 — Remote DDR4 Calibration Check over JTAG

Script: `fpga/check_ddr_vcu118.tcl` (written 2026-09-29, **not yet run**).
Purpose: confirm the reset-polarity fix and DDR4 calibration **without anyone at the board** — no
LEDs, no UART, no extra cable. Uses only the on-board Digilent JTAG already attached to the host.

---

## Why the DDR controller tells us whether the reset fix worked

The MIG (DDR4 memory controller) is held in reset by `mig_sys_rst` (`fpga/rtl/chip_vcu118.sv:121`):

```systemverilog
assign mig_sys_rst = (~locked) | (~eos) | (~rst_n_pad);
```

- **Old bitstream (2026-09-24):** board reset had the wrong polarity → MIG held in reset forever.
- **New bitstream (2026-09-25):** `rst_n_pad = ~rst_ni` → MIG leaves reset, calibrates (~1 s),
  reports pass/fail.

So the MIG's calibration status is a direct readout of the reset path. The CoralNPU core's reset comes
from the same `rst_n_pad` (via `clkgen_wrapper` → `rst_no = locked_pll & rst_ni & srst_ni`), so a
calibrated MIG strongly suggests the core is out of reset too.

---

## How it can be read remotely

Xilinx builds a **debug core** into the MIG, visible in the `.ltx` probes file as the `XSDBS_V2`
slave `i_ddr4/ddr_system_bd_i/ddr4_0` (`ipName=DDR4_SDRAM`). It exposes registers such as memory
type, rank count, byte count, calibration stage and pass/fail.

It sits behind the Vivado debug hub on the FPGA's **configuration JTAG** — the same Digilent cable
used for programming. Vivado's Hardware Manager can read it with no additional hardware.

This is how the reset bug was found on 2026-09-25: every register read back 0, with
`CRITICAL WARNING: [Xicom 50-46] ... MIG version registers have empty values`
(see `vcu118_progress.md`, Phase 6e).

---

## What the script does

1. `connect_hw_server`, then opens **only** the target matching serial `210308B76D4D`; refuses unless
   exactly one matches. (Host is shared — the other two Digilent cables belong to other users.)
2. Finds the `xcvu9p` on that JTAG chain.
3. Loads the probes file (`PROBES.FILE` / `FULL_PROBES.FILE`) so Vivado knows which debug cores exist.
4. `refresh_hw_device`, then `report_hw_mig` on every MIG debug core found.
5. Closes the target and disconnects.

**Read-only: it never programs the device or writes any register.**

Defaults: `.ltx` = `fpga/bitstreams/vcu118_highmem_2026-09-25/chip_vcu118.ltx`, serial =
`210308B76D4D`. The `.ltx` must match the bitstream currently on the board.

---

## Usage

```bash
cd ~/workspace/coralnpu

# 1. Program the bitstream with the reset fix (skip if already on the board)
vivado -mode batch -source fpga/program_vcu118.tcl \
  -tclargs fpga/bitstreams/vcu118_highmem_2026-09-25/chip_vcu118.bit

# 2. Read the MIG status
vivado -mode batch -source fpga/check_ddr_vcu118.tcl

# Other bitstream / cable:
vivado -mode batch -source fpga/check_ddr_vcu118.tcl -tclargs <path/to/chip_vcu118.ltx> <serial>
```

For the ROM-boot bitstream, pass its `.ltx` from
`bazel-bin/fpga/build.build_chip_vcu118_bitstream_highmem_rom/.../impl_1/chip_vcu118.ltx`.

---

## Reading the result

| Output | Meaning |
|---|---|
| Calibration **complete / pass**, memory type DDR4, real rank/byte counts, non-zero versions | Reset fix works, DDR calibrated. Board state = LED2–4 on |
| All registers 0, empty versions, `[Xicom 50-46]` warning | MIG still in reset — same as the 2026-09-24 bug |
| Calibration **failed** at a named stage | MIG left reset → **reset fix works**, but DDR training failed. Separate problem: suspect the remaining `mmcm_clkout0` / `c0_sys_clk_p` timing violations, or pins |
| `no MIG debug core found` | `.ltx` does not match the bitstream on the board, or the board was not programmed with it |
| `expected exactly one JTAG target` / `could not open target` | Cable not visible, or held open by another Vivado session |

---

## What it does not cover

- **CoralNPU execution.** It shows the reset path and DDR are alive, not that the core runs code.
  That is proven by the ROM-boot bitstream's UART heartbeat (`fpga/sw/rom_hello_test.c`).
- **DDR data integrity from the core's side.** Calibration passing ≠ the SoC's TL-UL → AXI → MIG path
  works. Needs a DDR read/write test program (not written yet).

---

## Results log

| Date | Bitstream | Result |
|---|---|---|
| 2026-09-25 | 2026-09-24 (reset bug) | all registers 0, `[Xicom 50-46]` — MIG in reset (manual Hardware Manager read, before this script existed) |
| | 2026-09-25 (reset fix) | *pending* |

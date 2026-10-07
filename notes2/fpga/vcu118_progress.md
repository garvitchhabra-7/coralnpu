# VCU118 Port — Progress Log

## Status (2026-10-07): bring-up done through DDR. ROM boot, UART and DDR4 all work on the board.

| Plan task | Status | Bitstream |
|---|---|---|
| 7.1 Program + LEDs | DONE | `fpga/bitstreams/vcu118_highmem_2026-09-25/` (ITCM boot) |
| 7.2 UART | DONE, see `vcu118_task7_2_uart.md` | `fpga/bitstreams/vcu118_highmem_rom_2026-10-05/` (ROM boot) |
| 7.3 SPI program loading | SKIPPED, no FTDI MPSSE adapter | none |
| 7.4 DDR4 test | **DONE, `DDR PASS` on the board** | `fpga/bitstreams/vcu118_highmem_rom_2026-10-06_201108/` |
| 7.5 RISC-V JTAG debug | open, needs an adapter on PMOD0 | none |

Timing is still not met. It is documented in `vcu118_timing_fixes.md` and deliberately left as is
for now, to move on to image tests.

**Next: image tests (Phase 8).** See `vcu118_image_test_plan.md`. It is blocked on choosing a way
to load the model and images onto the board.

Last updated: 2026-10-07

---

## 2026-10-06 build: 35 MHz, DDR side on 100 MHz, DDR test in ROM

`bazelisk run //fpga:archive_chip_vcu118_bitstream_highmem_rom`, built 2026-10-06 20:11 and archived
automatically (the new target copies the bitstream and reports with a timestamp, see
`fpga/archive_vcu118_bitstream.sh`). Bitstream md5 `1fd72c7e…`. Built from commit `95dc65e8` plus
the uncommitted changes listed in that folder's `BUILD_INFO.txt`.

**Changes in this build:**
- **`clk_main` 40 → 35 MHz** (`fpga/BUILD`, `_VCU118_CLOCK_FREQUENCY_MHZ`). The real frequency is
  35.036 MHz.
- **SoC DDR side moved from the 300 MHz MIG UI clock to the MIG's 100 MHz `addn_ui_clkout1`:**
  - the SmartConnect in `ddr_system_bd` now has two clocks (S00 on `aclk1` at 100 MHz, M00 on
    `aclk` at 300 MHz);
  - `chip_vcu118.sv` has a reset synchroniser (`ddr_axi_rst`) for the new clock.
- **SmartConnect address segment widened from 512 MB to 2 GB at `0x80000000`.** It now matches the
  SoC's `ddr_mem` window and the 2 GB MIG. Before this, accesses above `0x9FFFFFFF` got a decode
  error.
- **DDR calibration status on `gpio_i[0]`** (2-flop synchroniser in `chip_vcu118.sv`), so software
  can poll it before touching DDR.
- **ROM image is now `rom_ddr_test_highmem`** (`fpga/sw/rom_ddr_test.c`) instead of
  `rom_hello_highmem`. It prints the same banner and heartbeat.
- **DDR checkpoints:** regenerated in `~/workspace/test_project`. The old ones are backed up in
  `fpga/bitstreams/vcu118_highmem_rom_2026-10-05/ddr4_dcp_backup_2026-09-22/`. The steps are in
  `fpga/ip/ddr4_vcu118/GENERATING_DDR4_IP.md`.

**Board result:** the DDR test passed. Its tests:
- calibration wait;
- single word at `0x80000000`;
- byte/halfword strobes;
- walking 1s/0s;
- 1 MB address pattern;
- address lines below and above 512 MB, up to the top word of the 2 GB window.

**Timing** (details and fixes in `vcu118_timing_fixes.md`, section "Results of the 2026-10-06
build"):
- WNS −2.351 ns, 1538 failing endpoints.
- `clk_main` itself is now clean (+2.200 ns), and so is the DDR-side bus logic on 100 MHz
  (+3.847 ns).
- Remaining:
  - false-looking CDC failures caused by the 35 MHz ratio (791 endpoints);
  - the 300 MHz SmartConnect/MIG domain (708 endpoints, −1.715 ns);
  - the MIG reset synchroniser (3 endpoints).

**Known risk while timing is open:** the 300 MHz violation sits on the DDR data path. The DDR test
passed, but a negative-slack path can fail intermittently (temperature, data patterns). If image
data read from DDR ever looks corrupted, suspect this first and rerun the ROM DDR test.

---

> The checklist below dates from 2026-09-25 and is kept for history. The ROM-boot route replaced
> its "SPI is the only load path" plan for 7.2 and 7.4.

## NEXT BOARD SESSION — CHECKLIST

**Key point: UART alone shows nothing.** The bitstream is ITCM-boot: ITCM is empty after programming,
the core idles, nothing prints. A program must be loaded first, and on this bitstream the **only** load
path is the SPI slave via an FTDI adapter on PMOD1. So the session needs **two** cables.

### Prerequisites — sort out BEFORE the session

| Item | Status | Notes |
|---|---|---|
| FTDI MPSSE adapter (USB → SPI) | **open — none attached to this host** | FT4232H (PID `0x6011`) works with `nexus_loader` as-is. FT232H breakout / C232HM (`0x6014`) needs the PID patch |
| `nexus_loader` builds on this host | **open** | see [7.4](#74-nexus_loader-swutilsnexus_loader) — plan: build with Nix outside Bazel |
| `nexus_loader` accepts the adapter's PID | open (only if not FT4232H) | `sw/utils/nexus_loader/main.cc:68` — replace constant with a `--pid` flag |
| `nexus_loader` SPI clock ≤ 12 MHz | **open — any adapter** | hardcoded 30 MHz (`main.cc:392-400`); add `--spi_divisor` |
| USB device permissions | **open — user handling** | FTDI nodes are `root:dialout 660`; `garvit` not in `dialout`. Vivado only works because `hw_server` runs as root. `dialout` also covers `/dev/ttyUSB*` (UART). FT4232H (`0x6011`) additionally needs a udev rule — `60-openocd.rules` only covers `0x6014` |
| Highmem ELFs built | open | `trivial_pass`, `clk_test`, `add_uint32_m1` — must be the **highmem** link (DTCM `0x100000`, CSR `0x200000`) |
| PMOD1 physical pin numbering | **unverified** | FPGA-pin side is verified from master XDC; header numbering + MISO level-shifter direction need UG1224 |
| micro-USB cable for USB UART | — | any micro-USB cable. **No separate USB-to-UART dongle** — the CP2105 bridge is on the board, behind the connector labelled *USB UART* |

### Steps, in order

1. **Program** (can also be done remotely beforehand — JTAG cable is attached):
   ```bash
   vivado -mode batch -source fpga/program_vcu118.tcl -tclargs fpga/bitstreams/vcu118_highmem_2026-09-25/chip_vcu118.bit
   ```
   The `.ltx` next to it is picked up automatically.
2. **LED check, no button pressed**: LED0 ON (`io_halted`, correct — idle), LED1 OFF (`io_fault`),
   LED2 ON within ~1 s (DDR calibrated), LED3/4 ON (DDR AXI ready). LED5/6 carry `ddr_ui_clk` /
   `ddr_ui_clk_sync_rst` — note their state too. Record by LED number.
   *Remote alternative:* `vivado -mode batch -source fpga/check_ddr_vcu118.tcl` reads the MIG
   calibration status over JTAG — see [`vcu118_ddr_check.md`](vcu118_ddr_check.md).
3. **UART**: micro-USB into the connector labelled **USB UART** (not USB JTAG). Expect
   `/dev/ttyUSB0` + `ttyUSB1`; open 115200 8N1 on **both** — only one reaches the FPGA.
   The console is `uart[1]` (`fpga/sw/uart.c` → `0x40010000`), which is now on the real TX/RX pins.
4. **SPI adapter** → PMOD1 (J52), wiring from `kDirMask = 0x0b`:

   | FTDI | Dir | Signal | FPGA pin |
   |---|---|---|---|
   | ADBUS0 | out | `spi_clk_i` | N28 (PMOD1_0) |
   | ADBUS3 | out | `spi_csb_i` | M30 (PMOD1_1) |
   | ADBUS1 | out | `spi_mosi_i` | N30 (PMOD1_2) |
   | ADBUS2 | **in** | `spi_miso_o` | P30 (PMOD1_3) |
   | GND | — | common ground | **do not skip** |

   MPSSE clock ≤ 12 MHz — **`nexus_loader` currently hardcodes 30 MHz**, needs the `--spi_divisor`
   patch (7.4). `nexus_loader` uses FTDI channel A only (`INTERFACE_A`); leave ADBUS7 unconnected.

   **Adapter options** (any FTDI chip with MPSSE; must have **3.3 V** I/O, never 5 V):

   | Adapter | PID | Connect with | Notes |
   |---|---|---|---|
   | FTDI **C232HM-DDHSL-0** cable | `0x6014` | its flying leads plug straight onto PMOD pins | **DDHSL = 3.3 V**. Do *not* buy C232HM-**E**DHSL-0 (5 V). Leads: orange=ADBUS0 (SCK), yellow=ADBUS1 (MOSI), green=ADBUS2 (MISO), brown=ADBUS3 (CS), black=GND |
   | FT232H breakout (e.g. Adafruit 2264) | `0x6014` | female–female jumper wires | labels D0=ADBUS0, D1=ADBUS1, D2=ADBUS2, D3=ADBUS3 |
   | FT4232H mini module (FTDI FT4232H-56Q) | `0x6011` | female–female jumper wires | works with `nexus_loader` unpatched, but needs a udev rule |

   `0x6014` adapters need the `--pid` patch (7.4).

   **Header**: J52, a standard 2×6 PMOD. Digilent convention: pins 1–4 = signals 0–3 (top row),
   5 = GND, 6 = VCC, 7–10 = signals 4–7 (bottom row), 11 = GND, 12 = VCC. So PMOD1_0..3 → pins 1–4,
   GND → pin 5 or 11. **Unverified for VCU118** — check the J52 pinout and silkscreen in UG1224.
   Never connect the adapter's power pin to the PMOD VCC pins.

   **Voltage**: FPGA side is 1.2 V (bank 47, `VCC1V2_FPGA`); the master XDC names the nets `*_LS`
   (level-shifted), so the header side is most likely 3.3 V. **Unverified** — confirm the header
   voltage and that the shifter on PMOD1_3 (MISO) can drive toward the header, in UG1224.
5. **Load + run**, always with `--highmem`; recover with `--soft_reset`, **never `--reset`**:
   1. `trivial_pass` → `PASS`
   2. `clk_test` → `PASS` (also confirms the 40 MHz clock table)
   3. `add_uint32_m1` → `Hello from CoralNPU!` (first RVV test)
   4. `dma_test` → pass/fail

Do **not** touch `0x80000000` before LED2 is on — it hangs the crossbar.

### Existing test programs in `fpga/sw/`

| Program | Does | On VCU118 |
|---|---|---|
| `trivial_pass_test.cc` | prints `PASS` | **first test** |
| `clk_test.c` | reads clock table, prints `PASS` | **yes** |
| `add_uint32_m1.cc` | one vector add, prints hello | **yes — first RVV test** |
| `dma_test.cc` | DMA copies with self-check | yes, after the above |
| `gpio_test.cc` | output/loopback check | **no** — GPIO tied off, loopback read fails |
| `spi_test.cc` | 4 bytes out of SPI master | smoke test only, nothing attached |
| `spi_flash_test`, `flash_tool*`, `rom_boot/` | SPI flash / ROM boot | no — flash ports removed |
| `display_test`, `i2c_camera_test`, `isp_cam_test` | Nexus display/camera | no |

**Missing: a DDR test.** Needed before MobileNet (its 4 MB tensor arena is in `.extdata` = DDR).

Also available without the board: `coralnpu_v2_sim_test` targets in `fpga/BUILD`
(`trivial_pass_highmem_sim_test`, `trivial_pass_sim_test` — SPI loader path, `clk_sim_test`,
`dma_sim_test`) run these on the `chip_verilator` SoC model. They test SoC + software, not the VCU118
top/pinout.

### Fallback: JTAG debug over PMOD0
Same C232HM cable, different header (J53), OpenOCD + GDB, ITCM/DTCM only, untested — see
[`vcu118_openocd_jtag_debug.md`](vcu118_openocd_jtag_debug.md).

### After that
DDR read/write test → MobileNet (Phase 8). MobileNet correctness: compare the 1000 int8 scores /
top-5 against the host reference for the same image (`demos/npu_image_classification/compare.py`);
top-1 must match.

---

## REBUILD 2026-09-25 — DONE

`bazelisk build //fpga:build_chip_vcu118_bitstream_highmem` — passed, 20:12 (~3.5 h; synth done 16:55).
Elab first via `//fpga:build_chip_vcu118_elab_only_highmem` — passed.

**Archived** (read-only, byte-identical to the Bazel outputs, gitignored):
```
fpga/bitstreams/vcu118_highmem_2026-09-25/
  chip_vcu118.bit   (xcvu9p-flga2104-2L-e, 2026/09/25 20:12:00)
  chip_vcu118.bin
  chip_vcu118.ltx
  chip_vcu118_timing_summary_routed.rpt
```

**Timing** (vs. the 2026-09-24 build):

| | 2026-09-24 (50 MHz) | 2026-09-25 (40 MHz) |
|---|---|---|
| `clk_main` setup | −2.356 ns, 5135 failing | **+1.460 ns, clean** |
| Hold | 3 failing (`clk_aon` −0.148) | **0 failing** (WHS +0.010) |
| `mmcm_clkout0` (DDR UI) setup | −0.855 ns, 3451 failing | −0.223 ns, 107 failing |
| Pulse width | 3 failing | 3 failing (−0.092) |
| Total failing endpoints | 8592 | **110** |

Remaining: `c0_sys_clk_p → mmcm_clkout0` WNS −1.398 (1 EP), `c0_sys_clk_p → mmcm_clkout6` −0.748 (2 EPs) —
likely MIG-internal CDC whose exceptions are missing because OOC DCPs carry no XDC timing constraints
(Vivado CRITICAL WARNING `[Project 1-863]` at start of synth). Calibration worked with similar
violations before; investigate only if DDR misbehaves.

**License gotcha (cost one failed run):** the Bazel FPGA rule does **not** see `LM_LICENSE_FILE` (which
`module load Vivado/2025.2` sets). `fusesoc.bzl` builds an explicit env from the `nonhermetic` repo,
which only captures `XILINX_VIVADO` and `XILINXD_LICENSE_FILE`. The rebase moved `nonhermetic` to
main's `rules/nonhermetic.bzl`, it was re-fetched without the variable, and synth failed with
`[Common 17-345] A valid license was not found for feature 'Synthesis'`. Fix:
```bash
export XILINXD_LICENSE_FILE=/var/keys/Xilinx-2026.lic
bazelisk sync --only=nonhermetic
grep LICENSE $(bazelisk info output_base)/external/nonhermetic/env.bzl   # must not be ""
```
Permanent option (not applied): `common --repo_env=XILINXD_LICENSE_FILE=/var/keys/Xilinx-2026.lic`
in `.bazelrc.user`. Note: the binary on this host is `bazelisk`, not `bazel`.

---

## CHANGES APPLIED 2026-09-25 (after rebase onto main `ddea421f`)

| # | Change | Where |
|---|---|---|
| 1 | Reset inverted at the pad (`rst_n_pad = ~rst_ni`), used at all 3 sites | `fpga/rtl/chip_vcu118.sv` |
| 2 | `PULLTYPE PULLDOWN` on L19, wrong "inverts at the pad" comment fixed | `fpga/pins_vcu118.xdc` |
| 3 | Core clock 40 MHz via new `_VCU118_CLOCK_FREQUENCY_MHZ` (shared `_CLOCK_FREQUENCY_MHZ` stays 50 for Nexus/Verilator) | `fpga/BUILD` |
| 4 | **Option A**: all 5 `spim_flash_*` ports removed from top, SPI flash master tied off (miso=1). BD23/BF22 no longer driven | `chip_vcu118.sv`, `pins_vcu118.xdc` |
| 5 | LTX fallback: rootname → sibling `chip_vcu118.ltx` → `<rootname>.runs/impl_1/chip_vcu118.ltx` | `fpga/program_vcu118.tcl` |
| new | **UART swap**: `uart[1]` now on the real CP2105 TX/RX (BB21/AW25), `uart[0]` on CTS/RTS stubs. `fpga/sw/uart.c` prints to UART1 (`0x40010000`) and Nexus puts uart[1] on its USB UART — the old mapping would have given **no console output**. | `pins_vcu118.xdc` |
| new | `AddrWidth` param plumbed through (mirrors main's `chip_nexus.sv` change) | `chip_vcu118.core`, `chip_vcu118.sv` |
| new | `elab_only` build type for VCU118 (`//fpga:build_chip_vcu118_elab_only_highmem`, ~minutes) | `fpga/BUILD` |

Notes on the fixes:
- **Option B (LED5/LED6) was never viable**: AU37/AV36 already carry `ddr_ui_clk` / `ddr_ui_clk_sync_rst`.
- **`spim_flash_rst_no` was worse than recorded**: it is `gpio_o[4]` (`coralnpu_soc.sv:165`), reset value 0,
  not gated by `gpio_en` — so BF22 was driven LOW permanently, not just during SoC reset.
- Consequence of Option A: the `_rom` VCU118 variants can no longer boot from SPI flash. Nothing lost —
  the old mapping never reached a flash either (sclk/mosi/miso went to an empty PMOD0, csb/rst to push
  buttons). The board **does** have flash (the dual-QSPI config flash); see
  [Phase 9](#phase-9-optional--boot-from-on-board-qspi-flash) for how to use it later.
- UART baud: `uart.c` reads the core frequency at runtime from the clock table (`clk_get_main_freq_mhz`),
  so 40 MHz needs no software change.
- LEDs 5/6 (`ddr_ui_clk`, `ddr_ui_clk_sync_rst`) are also driven — include them when recording LED state.

---

## ORIGINAL CHANGE LIST (kept for reference — items 1-5 now applied, see above)

### 1. BLOCKER — Invert the reset at the pad (`fpga/rtl/chip_vcu118.sv`)

VCU118 `CPU_RESET` is **active HIGH**; the design treats `rst_ni` as active LOW with no inversion,
so the SoC and the MIG are held in reset forever. Confirmed on hardware — see Phase 6e below.

Add near the top of the module body:

```systemverilog
  // VCU118 CPU_RESET (L19) is an active-HIGH push button (board.xml rst_polarity=1,
  // "CPU Reset Push Button, Active High"). Invert at the pad so the rest of the design
  // sees an active-low reset, matching chip_nexus.sv conventions.
  logic rst_n_pad;
  assign rst_n_pad = ~rst_ni;
```

Then replace `rst_ni` with `rst_n_pad` at exactly these three sites:

| Line | Current | Becomes |
|---|---|---|
| 117 | `assign mig_sys_rst = (~locked) \| (~eos) \| (~rst_ni);` | `... \| (~rst_n_pad);` |
| 280 | `.rst_ni(rst_ni),` (i_clkgen) | `.rst_ni(rst_n_pad),` |
| 281 | `.srst_ni(rst_ni),` (i_clkgen) | `.srst_ni(rst_n_pad),` |

Do **not** rename the port itself — `fpga/pins_vcu118.xdc:48` binds `rst_ni` to L19.
Keep each polarity as-is: `mig_sys_rst` is asserted HIGH to the MIG, `clkgen_wrapper` wants
active LOW. Same signal, three sites, nothing else.

**Do not add a debouncer.** `rst_ni` is consumed only as a combinational level (no edge detect,
no counter, no state machine), so switch bounce just re-asserts the reset for a few ms and the
settled level wins. MIG calibration takes ~100 ms-1 s, far longer than the bounce window.
Power-on reset is already covered without the button: `rst_no = locked_pll & rst_ni & srst_ni`
gates the SoC on MMCM lock, and `mig_sys_rst` gates the MIG on STARTUPE3 `eos`.

### 2. Give the reset pin a defined idle level (`fpga/pins_vcu118.xdc:48`)

After change 1 the unpressed level *is* the run/no-run state, so it must not float:

```
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS12 PULLTYPE PULLDOWN } [get_ports { rst_ni }];
```

(The JTAG pins already use `PULLTYPE PULLDOWN`; the board should have an external pull-down for an
active-high button, but this is free insurance.)

### 3. Drop the core clock 50 → 40 MHz (`fpga/BUILD:26`)

`_CLOCK_FREQUENCY_MHZ = "50"` → `"40"`. Closes the −2.356 ns setup failure on `clk_main`
(needs 22.36 ns → max ~44.7 MHz). `CLKOUT0_DIVIDE_F` is computed from it
(`clkgen_xilultrascaleplus_vcu118.sv:51`, `1200.0 / ClockFrequencyMhz`) and `fpga/sw/uart.c:22`
derives the UART NCO from the core frequency, so the baud rate follows automatically.
See [Timing Analysis](#timing-analysis-2026-09-25) — this does **not** fix the DDR4 UI domain.

### 4. Get `spim_flash_csb_o` / `spim_flash_rst_no` off the push-button pins

**How they got there**: `fpga/pins_vcu118.xdc:84-88`. PMOD0 has 8 pins — JTAG took 5
(tck/tms/tdi/tdo/trst), SPI flash sclk/mosi/miso took the other 3. Nothing was left, so `csb` and
`rst_n` were parked on nearby pins that happen to be push buttons. (That comment also says
"Bank 67"; they are actually **Bank 64**.)

The implemented design drives **outputs** onto two of the five directional push buttons — confirmed
in `chip_vcu118_io_placed.rpt`:

```
| BD23 | spim_flash_csb_o  | OUTPUT | LVCMOS18 | bank 64 |   <- GPIO_SW_C (centre button)
| BF22 | spim_flash_rst_no | OUTPUT | LVCMOS18 | bank 64 |   <- GPIO_SW_W (west button)
```

Both ports pass straight through to `coralnpu_soc` (`chip_vcu118.sv:340,344`). The buttons are
active-high, so pressing one ties the net to `VCC1V8_FPGA` while the FPGA may be driving it low —
the 1.8 V rail fighting an output driver.

**The two are not equally risky, and the dangerous one is live right now:**

| Pin | Button | Signal | Idle state | Risk |
|---|---|---|---|---|
| BD23 | GPIO_SW_C (centre) | `spim_flash_csb_o` | HIGH (chip select deasserted) | low — agrees with a pressed button |
| BF22 | GPIO_SW_W (west) | `spim_flash_rst_no` | **LOW during SoC reset** | real |

`spim_flash_rst_no` is an active-low reset to the flash, so it is driven LOW whenever the SoC is in
reset — and with the polarity bug the board is in reset permanently. BF22 is being held low right
now. **Until this is fixed, press only the CPU_RESET button; never the 5-way cluster.**

Severity depends on whether there is a series resistor between switch and pin — that needs the
UG1224 schematic and has **not** been verified. Do not assume damage has occurred; do not assume it
cannot.

#### Fix — Option B (RECOMMENDED for the next rebuild): move them, XDC only

LEDs 5 and 6 are unused (the design drives LEDs 0-4 only). Replace the two lines at
`fpga/pins_vcu118.xdc:87-88` with:

```
# AU37 = GPIO_LED5, AV36 = GPIO_LED6, Bank 42 VCC1V2_FPGA — unused by this design.
# Parked here to keep spim_flash_* off the GPIO_SW_C / GPIO_SW_W push buttons.
set_property -dict { PACKAGE_PIN AU37 IOSTANDARD LVCMOS12 } [get_ports { spim_flash_csb_o }];
set_property -dict { PACKAGE_PIN AV36 IOSTANDARD LVCMOS12 } [get_ports { spim_flash_rst_no }];
```

**The IOSTANDARD must change to LVCMOS12** — Bank 42 is a 1.2 V bank, unlike Bank 64's 1.8 V.
Getting this wrong reproduces a DRC BIVB-class error and costs another 6 h.

Why B over A for *this* build: change 1 already touches RTL, and stacking an unrelated port-list
change into the same 6-hour run adds risk for no benefit. B is a two-line constraint edit that
cannot affect anything else. Bonus: `spim_flash_rst_no` on LED5 gives a free visual readout of the
SoC reset state — the exact signal this whole phase has been chasing.

#### Fix — Option A (cleaner end state, do it whenever the port list is next touched)

Remove all five `spim_flash_*` ports from the top level and tie them off internally, exactly as GPIO
was handled in bitstream-debug error #2. Frees 5 pins and removes the hazard by construction. Costs
SPI-flash boot, which is unused: the demo is ITCM boot over the SPI slave, and no flash was ever
wired to the pins this design used. Only revisit if a `_rom` boot variant is ever wanted on VCU118 —
see [Phase 9](#phase-9-optional--boot-from-on-board-qspi-flash).

### 5. Fix `fpga/program_vcu118.tcl` probes path

The script derives the LTX as `[file rootname $bitfile].ltx`, which for the Bazel-named bitstream
resolves to `com.google.coralnpu_fpga_chip_vcu118_0.1.ltx` — a file that does not exist, so the
probes were silently never loaded (no `Probes :` line in the run log). The real LTX is
`chip_vcu118.ltx` in `impl_1/`, or the copy in `fpga/bitstreams/vcu118_highmem_2026-09-24/`.
Fall back to a sibling `chip_vcu118.ltx` when the rootname-derived path is missing.

### 6. `nexus_loader` — three fixes before it can be used

See [7.4](#74-nexus_loader-swutilsnexus_loader) for detail: hardcoded
`kFtdiPid = 0x6011`, missing `libftdi1`/`libusb-1.0` headers on this host, and `--reset` being
Nexus-only (use `--soft_reset`).

### 7. Correct two factual errors in the docs

- `fpga/pins_vcu118.xdc:44-45` claims "`chip_vcu118.sv` inverts at the pad". **It does not** —
  that comment describes an intent that was never implemented, and is the reason the bug survived
  review. Fix the comment when making change 1.
- `vcu118_bitstream_debug.md:160` records Error #2's root cause as "HP banks on UltraScale+ do not
  support LVCMOS12". **This cannot be right**: `rst_ni` is LVCMOS12 on HP bank 73 — the same bank as
  DIP switches B17/G16/J16 — and it placed fine and shipped in the bitstream (`chip_vcu118_io_placed.rpt`
  confirms `L19 | rst_ni | High Performance | INPUT | LVCMOS12 | 73 | FIXED`). Bank 73's VCCO is
  `VCC1V2_FPGA`, so LVCMOS12 is the correct standard there. The DRC error was real but the recorded
  explanation is not; mark it unverified and re-derive if GPIO is ever wanted back.

### 8. Investigate, do not guess

- **DDR4 MIG UI domain** setup failure (`mmcm_clkout0`, −0.855 ns, 3451 endpoints). Calibration
  succeeds despite it (proven on hardware), but this is the path MobileNet's DDR traffic uses.
- **3 hold violations** on `clk_aon` (WHS −0.148 ns) and **3 pulse-width** violations. Hold
  failures cannot be fixed by slowing any clock and can fail functionally at any frequency.

---

## Completed Work

### Phase 1: RTL Board Wrapper — DONE

**`fpga/rtl/chip_vcu118.sv`** — adapted from `chip_nexus.sv`

- Module renamed to `chip_vcu118`
- Camera DVP ports removed from module port list (ISP inputs tied off inside):
  ```
  .ISP_DVP_D0(1'b0), ... .ISP_DVP_D7(1'b0),
  .ISP_DVP_PCLK(1'b0), .ISP_DVP_HSYNC(1'b0), .ISP_DVP_VSYNC(1'b0),
  .CAM_INT(1'b0), .CAM_TRIG()
  ```
- DDR4 MIG still instantiates `ddr_system_bd_ddr4_0_0` (works with `ddr4_stub` for initial synth)
- Everything else kept identical: STARTUPE3, dmi_jtag, IOBUF, UART, SPI, GPIO, I2C, DDR4 AXI wiring

### Clock Generation — DONE (separate files)

**Decision**: VCU118 has no 100 MHz clock. Using 125 MHz LVDS from SI5335A (AY24/AY23).

Created separate VCU118 clkgen files to avoid modifying the shared Nexus ones:

- **`fpga/rtl/clkgen_xilultrascaleplus_vcu118.sv`** — `CLKIN1_PERIOD=8.0`, `DIVCLK_DIVIDE=5`, `CLKFBOUT_MULT_F=48.0` (125/5 × 48 = 1200 MHz VCO, same as Nexus 100 × 12.0)
- **`fpga/rtl/clkgen_wrapper_vcu118.sv`** — defines `module clkgen_wrapper` (same name as Nexus) but instantiates `clkgen_xilultrascaleplus_vcu118`. FuseSoC only includes files from the active .core, so no conflict.

All output frequencies unchanged: 50 MHz core, 100 MHz SPI master, 10 MHz ISP (still generated to avoid CDC issues even though camera is unused).

### Phase 3: Pin Constraints — DONE (fully verified)

**`fpga/pins_vcu118.xdc`** — cross-checked against `part0_pins.xml` and VCU118 master XDC (XTP450).

PMOD pin mapping discovered from master.xdc:
- **PMOD0 (J53)** = Bank 67, LVCMOS18: AY14, AY15, AW15, AV15, AV16, AU16, AT15, AT16
- **PMOD1 (J52)** = Bank 47, LVCMOS12: N28, M30, N30, P30, P29, L31, M31, R29

| Signal | Pin | IOSTANDARD | Verification |
|---|---|---|---|
| clk_p_i (125 MHz) | AY24 | LVDS | Verified: part0_pins.xml sysclk_125_p |
| clk_n_i | AY23 | LVDS | Verified: part0_pins.xml sysclk_125_n |
| rst_ni (CPU_RESET) | L19 | LVCMOS12 | Verified: part0_pins.xml |
| uart_tx_o[0] | BB21 | LVCMOS18 | Verified: part0_pins.xml USB_UART_TX |
| uart_rx_i[0] | AW25 | LVCMOS18 | Verified: part0_pins.xml USB_UART_RX |
| uart_tx_o[1] | BB22 | LVCMOS18 | Stub on USB_UART_CTS (no 2nd channel) |
| uart_rx_i[1] | AY25 | LVCMOS18 | Stub on USB_UART_RTS (no 2nd channel) |
| i2c_scl | AM24 | LVCMOS18 | Verified: part0_pins.xml IIC_SCL_MAIN |
| i2c_sda | AL24 | LVCMOS18 | Verified: part0_pins.xml IIC_SDA_MAIN |
| LEDs 0-6 | AT32,AV34,AY30,BB32,BF32,AU37,AV36 | LVCMOS12 | Verified: part0_pins.xml |
| DIP switches 0-3 | B17,G16,J16,D21 | LVCMOS12 | Verified: part0_pins.xml |
| JTAG (tck,tms,tdi,tdo,trst) | AY14,AY15,AW15,AV15,AV16 | LVCMOS18 | Verified: master.xdc PMOD0_0-4_LS |
| SPI slave (clk,cs,mosi,miso) | N28,M30,N30,P30 | LVCMOS12 | Verified: master.xdc PMOD1_0-3_LS |
| SPI master (sclk,cs,mosi,miso) | P29,L31,M31,R29 | LVCMOS12 | Verified: master.xdc PMOD1_4-7_LS |
| SPI flash (sclk,mosi,miso) | AU16,AT15,AT16 | LVCMOS18 | Verified: master.xdc PMOD0_5-7_LS |
| SPI flash (csb,rst) | BD23,BF22 | LVCMOS18 | Placeholder (push buttons) — not needed for demo |

**Key findings:**
- VCU118 CP2105 only exposes 1 UART channel to user logic. Second channel goes to system controller.
- PMOD pins are NOT in board XML files but are in the master XDC (XTP450).
- PMOD1 (J52) is Bank 47, LVCMOS12 — not LVCMOS18 as initially assumed.
- Part number confirmed: `xcvu9p-flga2104-2L-e` (capital L, -2L speed grade)
- Reset is active HIGH per board.xml (rst_polarity=1). **WARNING: the original note here claimed
  `chip_vcu118.sv` inverts at the pad. IT DOES NOT.** The inversion was never written; the file is
  byte-identical to `chip_nexus.sv` on all three `rst_ni` sites. This is the bug found on hardware
  2026-09-25 — see [Changes To Be Made](#changes-to-be-made--start-here) item 1.
- `CPU_RESET` (L19) is a **dedicated** push button: it appears exactly once in the master XDC, and
  `board.xml` lists it as its own component (`sub_type="system_reset"`, part `TL3301EF100QG`),
  separate from `push_buttons_5bits` (the 5-way C/W/E/S/N cluster on BB24/BF22/BE22/BE23/BD23).

### Phase 4: FuseSoC and Build Integration — DONE

**`fpga/chip_vcu118.core`**
- Part: `xcvu9p-flga2104-2L-e`
- Toplevel: `chip_vcu118`
- References VCU118-specific clkgen files and `vivado_pre_opt_hooks_vcu118.tcl`
- Same parameters/defines as Nexus (FPGA_XILINX, USE_GENERIC, TB_SUPPORT, VLEN_128, ZVE32F_ON)

**`fpga/vivado_pre_opt_hooks_vcu118.tcl`**
- Removed `source pblock_u_isp.tcl` and `source pblock_u_ddr.tcl`
- Kept LSU MUXF_REMAP and MAX_FANOUT constraints

**`fpga/BUILD`**
- Added `VIVADO_HOOKS_VCU118` list
- Added `VCU118_COMMON_SRCS` and `VCU118_COMMON_CORES`
- Added `_VCU118_NAME_MAP` generating targets for all mem_configs × boot_modes × build_types
- Build targets like: `build_chip_vcu118_bitstream_highmem`, `build_chip_vcu118_synth_only_highmem`
- All tagged `manual`

---

### Phase 5: Initial Synthesis (No DDR4) — DONE (2026-09-21)

**Command**: `bazel build //fpga:build_chip_vcu118_synth_only_highmem`

Required `XILINXD_LICENSE_FILE=/var/keys/Xilinx-2026.lic` and `bazel sync --only=nonhermetic` to pass the license through Bazel's nonhermetic repo rule.

**Result**: 0 errors, 0 critical warnings, 1214 warnings (async reset DSP/BRAM advisory, same as Nexus).

**Utilization report**: located in Bazel execroot (not bazel-bin — Vivado writes it but the BUILD rule doesn't declare it as an output):
```
~/.cache/bazel/_bazel_garvit/39ac261a628125306e33bba905b154a7/execroot/coralnpu_hw/bazel-out/k8-fastbuild/bin/fpga/build.build_chip_vcu118_synth_only_highmem/com.google.coralnpu_fpga_chip_vcu118_0.1/synth-vivado/com.google.coralnpu_fpga_chip_vcu118_0.1.runs/synth_1/chip_vcu118_utilization_synth.rpt
```

**Resource utilization (post-synth, pre-opt):**

| Resource | Used | Available | Util% | Notes |
|---|---|---|---|---|
| CLB LUTs | 534,970 | 1,182,240 | 45.25% | Pre-opt; typically drops 30-50% after opt_design |
| Registers | 128,247 | 2,364,480 | 5.42% | |
| BRAM | 0 | 2,160 | 0% | Vivado mapped TCMs to URAMs instead |
| URAM | 384 | 960 | 40% | 384 × 288Kb = ~13.5 MB for TCMs |
| DSP48E2 | 187 | 6,840 | 2.73% | FPU + vector MUL/FALU |
| MMCM | 1 | 30 | 3.33% | clkgen_xilultrascaleplus_vcu118 |
| IOB | 70 | 832 | 8.41% | |
| SLR crossings | 0 | 17,280/edge | 0% | Everything fits in one SLR |

**Key observations:**
- LUT count is higher than the original 7% estimate because this is pre-opt and the highmem RVV variant is a large design. Post-opt will be significantly lower.
- Vivado chose URAMs over BRAMs for the 1MB TCMs — this is optimal (URAMs are 8× denser per tile, and 40% URAM usage leaves plenty of headroom).
- No black boxes — everything resolved including `ddr4_stub`.
- Zero SLR crossings — no pblock constraints needed.
- MMCME4_ADV (not MMCME2_ADV) instantiated — Vivado auto-upgraded the primitive for UltraScale+.

---

### Phase 2: DDR4 MIG IP Generation — DONE (2026-09-22)

Generated interactively in Vivado GUI (`/home/garvit/workspace/test_project/`):

**Block design approach** (matching Nexus): DDR4 MIG + AXI SmartConnect wrapper.
- Block design name: `ddr_system_bd` → wrapper module: `ddr_system_bd_wrapper`
- DDR4 IP configured via board preset: **DDR4 SDRAM C1** on VCU118
- Memory part: MT40A256M16LY-062E (auto-selected by board preset)
- Reference clock: 250 MHz (board preset `default_250mhz_clk1`, pins E12/D12, Bank 71)
- MIG native AXI: 512-bit data / 31-bit addr (not user-configurable)
- SmartConnect converts: **256-bit/34-bit/1-bit-ID** slave ↔ 512-bit/31-bit MIG master
- Debug ports (`dbg_bus_0`, `dbg_clk_0`) left external but unconnected
- `c0_ddr4_ui_clk` made external (needed by `chip_vcu118.sv` as DDR AXI clock domain)
- `c0_ddr4_aresetn` made external (driven from `~c0_ddr4_ui_clk_sync_rst` in RTL, same as Nexus)
- No Processor System Reset IP needed — Nexus doesn't use one either
- Generated with "Out of context per IP"

**Key differences from Nexus MIG (`ddr_system_bd_ddr4_0_0`)**:
| | Nexus | VCU118 |
|---|---|---|
| Module | `ddr_system_bd_ddr4_0_0` (raw MIG, 256-bit AXI) | `ddr_system_bd_wrapper` (MIG + SmartConnect) |
| DDR4 data width | 72-bit (ECC) | 64-bit (non-ECC) |
| AXI data width | 256-bit (native) | 256-bit (via SmartConnect upsizer to 512-bit MIG) |
| AXI port names | `c0_ddr4_s_axi_*` | `S00_AXI_0_*` |
| DDR4 pin names | `c0_ddr4_*` | `C0_DDR4_0_*` |
| Ref clock | 300 MHz | 250 MHz |
| Has parity pin | Yes | No (has `dm_n` instead) |
| Debug ports | Individual signals (dbg_clk, dbg_rd_data_cmp, ...) | Bundled `dbg_bus_0[511:0]`, `dbg_clk_0` |
| Ctrl AXI | Exposed | Internal to wrapper |

### Phase 6: DDR4 Integration — DONE (2026-09-22)

**`fpga/rtl/chip_vcu118.sv`** — Updated DDR4 instantiation:
- Module: `ddr_system_bd_ddr4_0_0` → `ddr_system_bd_wrapper`
- Top-level DDR4 ports adapted: 64-bit DQ, 8-bit DQS/DM, single-rank widths, `dm_n` replaces `parity`
- AXI port mapping: internal `c0_ddr4_s_axi_*` wires → wrapper's `S00_AXI_0_*` ports
- DDR4 ctrl AXI tied off (not exposed by wrapper; no ECC on VCU118)
- Removed all Nexus-specific debug signal declarations
- Reset logic unchanged: `c0_ddr4_aresetn = ~c0_ddr4_ui_clk_sync_rst`

**`fpga/ip/ddr4_vcu118_stub/`** — New VCU118-specific DDR4 stub (created):
- `rtl/ddr4_vcu118_stub.sv` — defines `ddr_system_bd_wrapper` with matching ports for synth-only builds
- `ddr4_vcu118_stub.core` — provides `xilinx:virtual:ddr4_0`
- `pins_ddr_vcu118_stub.xdc` — IOSTANDARD declarations for DDR4 pins
- `BUILD` — filegroup for Bazel

**`fpga/BUILD`** — VCU118 targets updated:
- New `DDR_VCU118_CORES` and `DDR_VCU118_SRCS` (point to `ddr4_vcu118_stub`)
- `VCU118_COMMON_SRCS/CORES` use VCU118-specific DDR4 instead of shared `DDR_CORES/SRCS`

**`fpga/pins_vcu118.xdc`** — DDR4 ref clock updated:
- Was: 300 MHz (G31/F31) — incorrect, from Nexus copy
- Now: 250 MHz CLK1 (E12/D12, Bank 71, DIFF_SSTL12, period 4.0 ns)

### Pin Verification — DONE (2026-09-22)

PMOD pins verified from VCU118 master XDC (XTP450). All pins now verified except
`spim_flash_csb_o` and `spim_flash_rst_no` (push button placeholders — SPI flash not needed for demo).

### Phase 6b: Real DDR4 IP Integration (DCP-based) — DONE (2026-09-22)

Replaced the DDR4 stub with pre-synthesized design checkpoints (DCPs) from the Vivado-generated block design. This is needed for bitstream builds — the stub only provides port-level synthesis.

**Why DCPs instead of RTL?** The internal Coral repo (`//internal/fpga/ip/ddr4`) has proprietary Xilinx MIG RTL checked in directly. The open-source repo can't include that, so we use pre-synthesized DCPs from the Vivado project instead. The DCPs contain the synthesized netlists for `ddr4_0_0` and `smartconnect_0_0` as black boxes.

**`fpga/ip/ddr4_vcu118/`** — New directory (created):
- `rtl/ddr_system_bd_wrapper.v` — block design wrapper (from Vivado)
- `rtl/ddr_system_bd.v` — block design netlist (instantiates ddr4_0_0 + smartconnect_0_0 as black boxes)
- `dcp/ddr_system_bd_ddr4_0_0.dcp` (5.8 MB) — pre-synthesized MIG IP
- `dcp/ddr_system_bd_smartconnect_0_0.dcp` (1.7 MB) — pre-synthesized SmartConnect
- `xdc/ddr_system_bd_ddr4_0_0.xdc` (26 KB) — MIG pin locations and timing constraints
- `xdc/ddr_system_bd_ddr4_0_0_board.xdc` — board-level pin mapping
- `vivado_ddr4_vcu118_setup.tcl` — Tcl script sourced by `vivado_setup_hooks.tcl` to load DCPs via `add_files`
- `ddr4_vcu118.core` — FuseSoC core: RTL as `verilogSource`, DCPs/XDCs/Tcl as `user` with `copyto`
- `BUILD` — filegroup including all *.dcp, *.xdc, *.tcl, *.v, *.core

**`fpga/vivado_setup_hooks.tcl`** — Modified:
- Added conditional sourcing of `vivado_ddr4_vcu118_setup.tcl` when present in workroot

**`fpga/BUILD`** — Updated:
- `DDR_VCU118_CORES` and `DDR_VCU118_SRCS` now point to `//fpga/ip/ddr4_vcu118` (real IP, not stub)
- Stub remains available at `//fpga/ip/ddr4_vcu118_stub` for synth-only builds if needed

**DCP loading flow:**
1. FuseSoC `copyto` places DCPs into `ddr4_vcu118_dcp/` and XDCs into `ddr4_vcu118_xdc/` in the workroot
2. `vivado_setup_hooks.tcl` sources `vivado_ddr4_vcu118_setup.tcl`
3. The setup Tcl calls `add_files` for each DCP and marks them for synthesis + implementation
4. MIG constraint XDCs added to `constrs_1` fileset

**Synthesis result**: Passed cleanly with real DDR4 IP.

---

### Phase 6c: Bitstream Build — DONE (2026-09-25)

**Command**: `bazel build //fpga:build_chip_vcu118_bitstream_highmem`

Five successive errors were debugged and fixed over multiple build iterations (~6 hours each). Full details in [`vcu118_bitstream_debug.md`](vcu118_bitstream_debug.md).

| # | Error | Root Cause | Fix |
|---|---|---|---|
| 1 | 118 missing DDR4 pin assignments | `BOARD_PART_PIN` silently fails without `BOARD_PART`; `dm_dbi_n`/`dm_n` mismatch; wrong hooks; `bg[1]` has no pin | Explicit pin XDC, renamed `dm_n`, board-aware hooks, narrowed `bg` |
| 2 | LVCMOS12 on HP bank (DRC BIVB-1) | GPIO DIP switches in HP banks 72/73 | Removed GPIO, tied off internally |
| 3 | Clock placement (Place 30-675) | JTAG TCK and SPI CLK on non-GCIO PMOD pins | `CLOCK_DEDICATED_ROUTE FALSE` |
| 4 | MMCM CLKFBOUT_MULT_F granularity (DRC AVAL-168) | 9.6 not a multiple of 0.125 | `DIVCLK_DIVIDE=5`, `CLKFBOUT_MULT_F=48.0` |
| 5 | Post-bitstream hook references `chip_nexus.bit` | Nexus calibration FW hook registered for VCU118 | Removed hook — DCP has calibration pre-stitched |

**Result**: Bitstream generated successfully (`chip_vcu118.bit`, `chip_vcu118.bin`).

**Build time**: ~6 hours (synthesis ~1.5h, implementation ~4h, bitstream ~0.5h).

**Known warnings** (the first one is blocking, the rest are cosmetic):
- `[Timing 38-282]` — timing violations present, and they are **not** cosmetic. Full numbers in [Timing Analysis](#timing-analysis-2026-09-25) below. Read that section before trusting any bring-up result.
- `[Constraints 18-4427]` — DCP property overrides (cosmetic, inherent to DCP flow)
- `[Vivado 12-4739]` — MIG internal hierarchy paths not found (DCP flow, constraints apply to flattened netlist)
- `[Project 1-840]` — DCP used instead of XCI (expected)

**Bitstream location**: originally only in the Bazel cache (evictable — `bazel clean` would have destroyed 6 hours of work). Archived 2026-09-25 to a stable path:

```
fpga/bitstreams/vcu118_highmem_2026-09-24/
  chip_vcu118.bit   80 MB   (design=chip_vcu118 part=xcvu9p-flga2104-2L-e built=2026/09/24 22:32:51)
  chip_vcu118.bin   80 MB
  chip_vcu118.ltx           (debug probes)
```

`fpga/bitstreams` is already in `.gitignore`, so the archive is not committed. The Bazel-cache copy still exists at:

```
bazel-bin/fpga/build.build_chip_vcu118_bitstream_highmem/com.google.coralnpu_fpga_chip_vcu118_0.1/synth-vivado/
```

---

### Boot Mode of the Built Bitstream — READ THIS FIRST

`build_chip_vcu118_bitstream_highmem` carries **no boot-mode suffix**, which per `_BOOT_MODES` (`fpga/BUILD:430`) means **ITCM boot**, i.e. `EnableAutoboot=0`, `BootAddr=0`, no ROM preloaded.

**The core comes up idle with an empty ITCM. It will not run anything on its own.** A program must be pushed in over the SPI slave (`nexus_loader`) or JTAG. Do not interpret "no UART output after programming" as a failure — that is the expected state.

The `_rom` variants (`build_chip_vcu118_bitstream_highmem_rom`) boot from SPI flash at `0x10000000` instead; those have not been built for VCU118.

---

### Phase 6d: Programming — DONE (2026-09-25)

**Verified: no CoralNPU bitstream has ever been written to any board.** The build log for
`build_chip_vcu118_bitstream_highmem` contains zero occurrences of `program_hw_devices`,
`open_hw_target`, `connect_hw_server`, or `open_hw_manager` — `bazel build` only runs
synth → impl → `write_bitstream`. There are no programming targets in `fpga/BUILD` or `rules/`.
The only board ever programmed on this host was `blinky` from `~/workspace/basic_fpga/` on
2026-09-21, to the cable below.

**Board identity**: the VCU118 is JTAG cable serial **`210308B76D4D`** (confirmed: the 2026-09-21
blinky run enumerated `xcvu9p_0` on it). VCU118 uses an onboard Digilent JTAG-SMT module, which
is why it appears as `0403:6014 Digilent USB Device`.

**`fpga/program_vcu118.tcl`** — created. Usage from the repo root:

```bash
vivado -mode batch -source fpga/program_vcu118.tcl
vivado -mode batch -source fpga/program_vcu118.tcl -tclargs <bitfile> <serial>
```

Defaults to cable `210308B76D4D` and the highmem bitstream under `bazel-bin`. Three guards
before any bits move:

1. Parses the `.bit` header and refuses unless the part is `xcvu9p*`.
2. Selects the cable **by serial**, never `[lindex [get_hw_targets] 0]`. Requires exactly one match.
3. Walks the JTAG chain for an `xcvu9p` rather than assuming device 0; checks `DONE` afterwards.

Dry-run (bad serial, stops before programming) was verified working, then the real run succeeded:

```
Device    : xcvu9p_0  (part xcvu9p)
Programming...
INFO: [Labtools 27-3164] End of startup status: HIGH
 chip_vcu118 -> 210308B76D4D : OK
```

`End of startup status: HIGH` is the authoritative confirmation that DONE went high — note the
script's own `REGISTER.IR.BIT5_DONE` check returned empty on this device driver and printed
"DONE status not reported", which is not a failure.

**CRITICAL — this host is shared.** `synthesia` has **three** Digilent JTAG cables attached, and
other users (`jayanta`, `rishabh`) have had Vivado sessions open since 2026-09-17. A positional
target pick will program someone else's board. Always pass/keep the serial.

```
localhost:3121/xilinx_tcf/Digilent/210308A5F7D4   (not ours)
localhost:3121/xilinx_tcf/Digilent/210308A7A488   (not ours)
localhost:3121/xilinx_tcf/Digilent/210308B76D4D   <- ours
```

---

### Timing Analysis (2026-09-25)

From `chip_vcu118_timing_summary_routed.rpt` in the impl_1 run directory.
**Design timing is NOT met**: WNS −2.356 ns, TNS −3073.352 ns, 8592 failing endpoints of 485621.

| Clock | WNS | Failing EPs | Note |
|---|---|---|---|
| `clk_main` (50 MHz core) | **−2.356 ns** | 5135 | needs 22.36 ns → **max ~44.7 MHz** |
| `mmcm_clkout0` (DDR4 MIG UI domain) | **−0.855 ns** | 3451 | inside DDR4 / SmartConnect |
| `clk_aon` | WHS **−0.148 ns** | 3 | **hold** violation |
| `mmcm_clkout0` | WPWS −0.184 ns | 3 | pulse width |

Clean clocks: `c0_sys_clk_p`, `jtag_tck_i`, `spi_clk_i`, `clk_spim_unbuf`, `mmcm_clkout5/6`.

**Three separate problems, do not conflate them:**

1. **Core clock setup** — fixable with a one-line change: `_CLOCK_FREQUENCY_MHZ = "50"` → `"40"`
   at `fpga/BUILD:26`. `CLKOUT0_DIVIDE_F` is computed from it
   (`clkgen_xilultrascaleplus_vcu118.sv:51`, `1200.0 / ClockFrequencyMhz`), and `fpga/sw/uart.c:22`
   derives the UART NCO from the core frequency, so baud tracks automatically. Nothing else changes.
2. **DDR4 MIG UI domain** — MIG-derived, so lowering the core clock does **not** help. This is the
   path MobileNet needs. Needs separate investigation.
3. **3 hold + 3 pulse-width violations** — hold violations cannot be fixed by slowing any clock and
   can fail functionally at any frequency. Must be inspected individually in the routed report.

---

### Phase 6e: First Board Bring-Up — RESET POLARITY BUG FOUND (2026-09-25)

**Symptom**: after programming, exactly **one** LED lit (LED0 `io_halted`). LED1-4 dark.

**Diagnosis path** (all of it done from the host, no scope, no extra hardware):

1. Read the DDR4 MIG's debug core over JTAG using the LTX (it contains an `XSDBS_V2` slave,
   `i_ddr4/ddr_system_bd_i/ddr4_0`, `ipName=DDR4_SDRAM`). **Every MIG register read back zero** —
   `MEM_TYPE=000`, `NUM_RANK=000`, `BYTES=000`, all map versions 0, plus
   `CRITICAL WARNING: [Xicom 50-46] ... MIG version registers have empty values`.
   That means the MIG never left reset. The fact that the debug hub *answered at all* proved the
   clocks were running, which ruled out a clocking failure.
2. Traced the reset. `chip_vcu118.sv` uses `rst_ni` at three sites, all combinational level logic,
   with **no inversion anywhere** — byte-identical to `chip_nexus.sv` (whose board reset is
   active-low, so it never needed one).
3. Confirmed the board's polarity from `board.xml`: `rst_polarity=1` on the interface mapping to
   `CPU_RESET`, and the component description literally reads
   `"CPU Reset Push Button, Active High"`.

So `CPU_RESET` idles LOW, the design reads that as "reset asserted", and it never starts.

**Mechanism** (note: the MMCM is *not* involved — `clkgen_xilultrascaleplus_vcu118.sv:109` ties
`.RST(1'b0)`, so it free-runs and locks regardless of the button):

```
clkgen_xilultrascaleplus_vcu118.sv:141
  assign rst_no   = locked_pll & rst_ni & srst_ni;   -> 0, holds the whole SoC in reset
  assign locked_o = locked_pll;                       -> 1, clocks ARE running

chip_vcu118.sv:117
  assign mig_sys_rst = (~locked) | (~eos) | (~rst_ni); -> 1, holds the MIG in reset
```

**HARDWARE CONFIRMATION**: holding the CPU_RESET button (which drives L19 HIGH = the level the
design wants) brought the board to life — **2 LEDs lit immediately, a 3rd ~1 second later**. The
~1 s delay is DDR4 calibration completing, exactly the timing `fpga/README.md` describes. Releasing
the button returns it to the dead state.

**This is a big result beyond the bug itself**: DDR4 calibration *succeeds* on VCU118. The MIG
config, the 250 MHz reference clock on E12/D12, the 116 explicit DDR4 pin assignments from
bitstream-debug error #1, and the DCP-based IP flow are all validated on real silicon. It also
shows the `mmcm_clkout0` timing violations do not prevent calibration.

**Everything is explained by the one bug.** No other root cause is outstanding for this symptom.

---

## Remaining Work

### Phase 7: Board Bring-Up — next step

Builds take ~6 hours, so **do not serialize this**. Suggested order:

#### 7.1 Program + LED check (free, no extra hardware)

```bash
vivado -mode batch -source fpga/program_vcu118.tcl
```

Five status signals are on LEDs, active high (`fpga/pins_vcu118.xdc:118-122`):

| LED | Pin | Signal | Expected | Observed 2026-09-25 |
|---|---|---|---|---|
| 0 | AT32 | `io_halted` | ON (core idle — correct for ITCM boot) | ON |
| 1 | AV34 | `io_fault` | OFF | OFF |
| 2 | AY30 | `ddr_cal_complete_o` | **ON within ~1 s** — highest-value bit in bring-up | only while CPU_RESET held |
| 3 | BB32 | `io_ddr_mem_axi_aw_ready` | ON once calibrated | only while CPU_RESET held |
| 4 | BF32 | `io_ddr_mem_axi_ar_ready` | ON once calibrated | only while CPU_RESET held |

With the **current** (unfixed) bitstream only LED0 lights; holding CPU_RESET brings up 2 more
immediately and a 3rd ~1 s later. After [change 1](#1-blocker--invert-the-reset-at-the-pad-fpgartlchip_vcu118sv)
this should be the steady state with no button held.

LED2 validates the 125 MHz LVDS input, the MMCM, the reset path, the 250 MHz DDR ref clock, and all
116 DDR4 pin assignments from bitstream-debug error #1 — **all of these are now confirmed good on
hardware** (Phase 6e).

Per `fpga/README.md`, DDR calibration is **not** instant. Do **not** touch `0x80000000` before
LED2 lights — it stalls the TLUL→AXI bridge and hangs the whole crossbar. Recover with
`nexus_loader --soft_reset`.

#### 7.2 Start the rebuild immediately (background, ~6 h) — DONE 2026-09-25, see [Rebuild](#rebuild-2026-09-25--done)

Apply [changes 1-4](#changes-to-be-made--start-here) *together* — reset inversion, the pin
pull-down, 50 → 40 MHz, and the push-button pin conflict — then kick the build off and do
everything below while it runs. Do not rebuild once per change.

#### 7.3 Cables — UART and SPI are two SEPARATE cables, neither connected as of 2026-09-25

Full bring-up needs **three** USB connections. Only the first is currently attached:

| # | Link | Connector | Status |
|---|---|---|---|
| 1 | FPGA config JTAG | on-board Digilent JTAG-SMT, its own micro-USB | **connected** (`210308B76D4D`) |
| 2 | UART console | on-board CP2105, the separate **USB UART** micro-USB | not connected |
| 3 | SPI program load | **no USB port exists** — PMOD1 header + your own FTDI MPSSE adapter | not connected |

USB state on `synthesia` is still just the three Digilent JTAG modules, and there is no
`/dev/ttyUSB*` at all.

- **UART**: micro-USB only, zero wiring. Plug into the connector labelled *USB UART* (not the
  USB JTAG one already in use). Gives `/dev/ttyUSB0` + `ttyUSB1`; only one channel reaches user
  logic (the other goes to the system controller). 115200 8N1 — `fpga/sw/uart.c:22` derives the NCO
  from the core frequency, so the baud follows a clock change.
- **SPI load**: there is **no** USB-to-SPI path on the board. The CP2105 serves only the UART and
  the on-board JTAG serves only the FPGA config TAP. You need your own FTDI MPSSE breakout wired
  onto **PMOD1 (J52)**. Which adapter matters: `nexus_loader` hardcodes `kFtdiPid = 0x6011`
  (FT4232H), so an FT4232H module works unpatched while a far more common FT232H breakout or
  C232HM cable (0x6014) needs the patch from change 6 first.

  Wiring, derived from `kDirMask = 0x0b` in `sw/utils/nexus_loader/spi_master.h`:

  | FTDI | Dir | Signal | PMOD1 | Pin |
  |---|---|---|---|---|
  | ADBUS0 | out | `spi_clk_i` | PMOD1_0 | N28 |
  | ADBUS3 | out | `spi_csb_i` | PMOD1_1 | M30 |
  | ADBUS1 | out | `spi_mosi_i` | PMOD1_2 | N30 |
  | ADBUS2 | **in** | `spi_miso_o` | PMOD1_3 | P30 |

  Plus common ground — do not skip it; a floating ground between two USB devices is the classic
  reason an MPSSE link reads garbage. Keep the MPSSE clock **≤ 12 MHz** (`pins_vcu118.xdc:65`
  constrains `spi_clk_i` at 83.333 ns). The master XDC names these `PMOD1_*_LS`, so they are
  level-shifted at the header rather than raw 1.2 V — but confirm in UG1224 that the shifter on
  PMOD1_3 is oriented FPGA→header before trusting MISO. The FPGA-pin side of this table is verified
  from the master XDC; the physical PMOD connector numbering is **not** — check UG1224 before wiring.

  **Possible shortcut**: the `_rom` build variants bake the ROM image into the bitstream at build
  time (`--MemInitFile=`, `--EnableAutoboot=1`). A ROM-boot bitstream with a small standalone
  program compiled in would run on power-up and print over UART with **no SPI cable at all**. That
  costs a build, but a rebuild is already required for changes 1-4, and no MPSSE adapter is on hand.

#### 7.4 `nexus_loader` (`sw/utils/nexus_loader/`)

Host-side C++ tool (~770 lines): drives an FTDI adapter in MPSSE (SPI) mode and talks to the SoC's
SPI slave (spi2tlul), which turns SPI commands into memory reads/writes. Loads ELFs into ITCM and
starts the core. Written for Google's Nexus board.

| Flag | Does |
|---|---|
| `--serial <S>` | **required** (`main.cc:357-360`) — opens only that adapter |
| `--highmem` | CSR base `0x200000` — **required for this bitstream** |
| `--load_elf`, `--verify` | load ELF sections, read back and compare |
| `--set_entry_point`, `--start_core` | set PC, release core |
| `--poll_halt <s>` | wait for program to halt |
| `--poll_status_addr/--poll_status_size` | read a status buffer after the run (results without UART) |
| `--read_word_addr`, `--write_word_addr`, `--read_data_addr`, `--load_data` | raw memory access (DDR test) |
| `--soft_reset` | SoC reset over SPI — use this |
| `--reset` | toggles PROG_B on Nexus wiring — **never on VCU118** |

Typical run:
```bash
nexus_loader --serial <adapter-serial> --highmem \
  --load_elf trivial_pass_test.elf --verify \
  --set_entry_point 0x0 --start_core --poll_halt 5
```

**Safe on the shared host:** `--serial` is mandatory and passed to `ftdi_usb_open_desc`, so it cannot
grab one of the three Digilent JTAG cables even though an FT232H adapter shares their `0403:6014`
VID:PID. (An earlier note here claimed serial selection was missing — wrong.)

What is still needed:

1. **`kFtdiPid = 0x6011`** (`main.cc:68`) is hardcoded to FT4232H. An FT232H-based adapter
   (0x6014) will not open. Replace with a `--pid` flag.
2. **It will not build on this host.** `BUILD.bazel` hardcodes `-I/usr/include/libftdi1` and
   `-I/usr/include/libusb-1.0` and links `-lftdi1 -lusb-1.0 -lelf`. Host state: `libelf` headers +
   runtime present; `libusb-1.0` runtime only (no headers); `libftdi1` absent. No sudo, so no `dnf`.
   Do **not** just add Nix `libftdi1`/`libusb1` to the Bazel build: Nix libs are built against a newer
   glibc than RHEL8's 2.28, so the binary would likely fail at load time (`GLIBC_2.xx not found`).
   **Plan:** a small script (e.g. `sw/utils/nexus_loader/build_nix.sh`) that compiles `main.cc` +
   `spi_master.cc` inside `nix-shell -p gcc abseil-cpp libftdi1 libusb1 elfutils` — fully Nix,
   consistent glibc, no repo build changes.
3. **SPI clock is hardcoded to 30 MHz.** `main.cc:392-400`: `DISABLE_CLK_DIV_5` (60 MHz base) +
   `SET_TCK_DIVISOR 0x0000` → SCK = 60 / (2·(0+1)) = 30 MHz, no flag to change it. VCU118 constrains
   `spi_clk_i` for 12 MHz (`pins_vcu118.xdc`, 83.333 ns), and the path goes through board level shifters
   + jumper wires. Add a `--spi_divisor` flag (2 → 10 MHz, 4 → 6 MHz). Needed for **any** adapter.
4. **Permissions** — see prerequisites table (`dialout`).
5. **Never use `--reset` on VCU118.** Leave ADBUS7 unconnected (PROG_B on Nexus). It toggles ADBUS7 expecting PROG_B wired to the FPGA — that
   is Nexus-only (and the README's recovery flow assumes `zturn` on a Zynq SOM, which VCU118 does
   not have). Use `--soft_reset` (SPI opcode 0x03); re-configure with `fpga/program_vcu118.tcl`.

Also pass **`--highmem`** so the CSR base is `0x200000`, not the default `0x30000`
(`coralnpu_soc.sv` selects the base from the TCM sizes).

#### 7.5 First real "it works" milestone

Load a trivial ELF (`//fpga:add_uint32_m1` or `//fpga:clk_test`) over SPI, then
`--verify`, `--set_entry_point`, `--start_core`, `--poll_halt`.

#### 7.6 Then

DDR4 read/write test at `0x80000000`, then JTAG debug (OpenOCD → RISC-V debug module; JTAG is on
PMOD0 pins AY14/AY15/AW15/AV15/AV16 and also needs an external adapter).

### Phase 8: MobileNet Demo — after bring-up

Build MobileNet v1 binary with TFLite Micro for highmem variant. Embed sample images as C arrays. Load → run → print classification on UART.

### Phase 9 (optional) — Boot from on-board QSPI flash

Not needed for the demo. Useful if a standalone board is wanted: program runs from power-up with no
SPI/MPSSE cable attached.

**What the board has** (from `master.xdc`, XTP450): dual 1 Gb Quad-SPI **configuration** flash
(QSPI0 + QSPI1, x8 dual-quad mode). It normally holds the bitstream.

| Flash | DQ0 | DQ1 | DQ2 | DQ3 | CS_B | Clock |
|---|---|---|---|---|---|---|
| QSPI0 | AP11 | AN11 | AM11 | AL11 | AJ11 | shared CCLK (AF13) |
| QSPI1 | AM19 | AM18 | AN20 | AP20 | BF16 | shared CCLK (AF13) |

- QSPI0 sits on **dedicated config pins (bank 0)** — reachable from user logic only through
  `STARTUPE3` (`DATA_IN`/`DATA_OUT`/`FCSBO`).
- QSPI1 data + CS are on **ordinary user I/O in bank 65** (LVCMOS18, VCC1V8_FPGA) — directly usable.
- `CCLK` is a dedicated pin shared by both. User logic can drive it **only** via
  `STARTUPE3.USRCCLKO` (currently tied to `1'b0` at `chip_vcu118.sv:112`, `USRCCLKTS` also 0).

**What it would take** (one RTL change + one rebuild):

1. Re-add the `spim_flash_*` connections in `chip_vcu118.sv`, but route them to QSPI1:
   MOSI → AM19 (DQ0), MISO ← AM18 (DQ1), CS → BF16. Hold DQ2/DQ3 (WP#/HOLD#) high or leave to
   board pull-ups — check UG1224.
2. Drive `spim_flash_sclk_o` into `STARTUPE3.USRCCLKO` instead of a pin.
3. `spim_flash_rst_no`: no reset pin for the flash appears in the master XDC, so leave it
   unconnected. **Unverified** — confirm in the UG1224 schematic whether RESET#/DQ3 is wired.
4. Program image placement: in dual-quad mode the bitstream is split nibble-wise across **both**
   chips starting at offset 0 (~80 MB `.bit` → ~40 MB per chip). The program must live above that.
   Check which flash address the ROM bootloader reads (`0x10000000` in CPU space) maps to, and add an
   offset if needed.
5. Writing the image: Vivado Hardware Manager can program the config flash (`write_cfgmem` +
   `program_hw_cfgmem`) with the bitstream **and** a data file at an offset in one go.

**Things to verify before building:**
- `USRCCLKO` hand-over: the first ~3 `USRCCLKO` edges after `EOS` are swallowed while the STARTUP
  block switches over from config clock; the bootloader must tolerate that (a dummy transfer first).
- SPI mode / frequency: the SoC's SPI flash master is single-bit SPI; MT25QU supports it. Keep SCLK
  well under the flash's read limit.
- Whether the ROM bootloader's flash command set matches the MT25QU (3- vs 4-byte addressing — 1 Gb
  needs 4-byte addressing above 16 MB, and the program sits above ~40 MB).

---

## Deviations from Original Plan

| Plan Said | Reality | Impact |
|---|---|---|
| "100 MHz clock, no clkgen changes" | VCU118 has no 100 MHz; using 125 MHz | Created separate `clkgen_*_vcu118.sv` files |
| "Reuse clkgen_wrapper.sv directly" | Needed VCU118-specific wrapper | `clkgen_wrapper_vcu118.sv` instantiates `clkgen_xilultrascaleplus_vcu118` |
| "Part: xcvu9p-flga2104-2-e" | Actual: `xcvu9p-flga2104-2L-e` (capital L) | Fixed in .core file |
| "2-channel UART via CP2105" | Only 1 channel exposed to user logic | UART1 stubbed on CTS/RTS pins |
| "PMOD pins from UG1224" | PMOD pins not in board XML or UG1224 | Found in master XDC (XTP450) |
| "I2C on spare PMOD pins" | I2C has dedicated on-board bus (AM24/AL24) | Better — no PMOD needed for I2C |
| "DDR4 MIG 256-bit AXI natively" | MIG AXI fixed at 512-bit/31-bit | Block design wrapper with SmartConnect for width conversion |
| "300 MHz DDR4 ref clock" | Board preset offers 250 MHz CLK1 | MIG PLL handles it; pins E12/D12 |
| "Reuse ddr4_stub directly" | Port names differ (wrapper vs raw MIG) | Created VCU118-specific `ddr4_vcu118_stub` |
| "Use MIG RTL from internal/" | Proprietary Xilinx RTL not in open-source repo | Used pre-synthesized DCPs from Vivado project instead |
| "CLKFBOUT_MULT_F=9.6 for 125 MHz" | 9.6 not a multiple of MMCME4 0.125 granularity | DIVCLK_DIVIDE=5, CLKFBOUT_MULT_F=48.0 (same 1200 MHz VCO) |
| "GPIO on DIP switches" | DIP switches in HP banks, incompatible with LVCMOS12 | GPIO removed, tied off internally (**root cause as recorded is wrong — see change 7**) |
| "chip_vcu118.sv inverts the reset at the pad" | The inversion was never written | Board held in reset; found on hardware 2026-09-25, see change 1 |
| "SPI flash csb/rst on spare push buttons" | Those pins are driven as outputs onto active-high buttons | Output-driver contention hazard, see change 4 |

---

## File Inventory

| File | Status | Based On |
|---|---|---|
| `fpga/rtl/chip_vcu118.sv` | Created | `chip_nexus.sv` |
| `fpga/rtl/clkgen_xilultrascaleplus_vcu118.sv` | Created | `clkgen_xilultrascaleplus.sv` (125 MHz params) |
| `fpga/rtl/clkgen_wrapper_vcu118.sv` | Created | `clkgen_wrapper.sv` |
| `fpga/pins_vcu118.xdc` | Created (verified) | `pins_nexus.xdc` + part0_pins.xml + bitstream debug |
| `fpga/chip_vcu118.core` | Created | `chip_nexus.core` |
| `fpga/vivado_pre_opt_hooks_vcu118.tcl` | Created | `vivado_pre_opt_hooks.tcl` (no ISP/DDR pblocks) |
| `fpga/BUILD` | Modified (VCU118 targets added) | Existing |
| `fpga/ip/ddr4_vcu118_stub/rtl/ddr4_vcu118_stub.sv` | Created | `ddr4_stub.sv` (VCU118 wrapper ports) |
| `fpga/ip/ddr4_vcu118_stub/ddr4_vcu118_stub.core` | Created | `ddr4_stub.core` |
| `fpga/ip/ddr4_vcu118_stub/pins_ddr_vcu118_stub.xdc` | Created | IOSTANDARD-only for stub |
| `fpga/ip/ddr4_vcu118_stub/BUILD` | Created | `ddr4_stub/BUILD` |
| `fpga/ip/ddr4_vcu118/rtl/ddr_system_bd_wrapper.v` | Created | Vivado block design wrapper |
| `fpga/ip/ddr4_vcu118/rtl/ddr_system_bd.v` | Created | Vivado block design netlist |
| `fpga/ip/ddr4_vcu118/dcp/ddr_system_bd_ddr4_0_0.dcp` | Created | Pre-synth MIG (5.8 MB) |
| `fpga/ip/ddr4_vcu118/dcp/ddr_system_bd_smartconnect_0_0.dcp` | Created | Pre-synth SmartConnect (1.7 MB) |
| `fpga/ip/ddr4_vcu118/xdc/ddr_system_bd_ddr4_0_0.xdc` | Created | MIG pin/timing constraints |
| `fpga/ip/ddr4_vcu118/xdc/ddr_system_bd_ddr4_0_0_board.xdc` | Created | Board pin mapping |
| `fpga/ip/ddr4_vcu118/vivado_ddr4_vcu118_setup.tcl` | Created | DCP loading Tcl hook |
| `fpga/ip/ddr4_vcu118/ddr4_vcu118.core` | Created | FuseSoC core (DCP-based) |
| `fpga/ip/ddr4_vcu118/BUILD` | Created | Bazel filegroup |
| `fpga/vivado_setup_hooks.tcl` | Modified | Added VCU118 DDR4 setup sourcing + board-aware pre-opt hooks |
| `fpga/ip/ddr4_vcu118/xdc/ddr4_vcu118_pins.xdc` | Created | 116 explicit PACKAGE_PIN constraints from board XML |
| `fpga/program_vcu118.tcl` | Created (dry-run verified) | Serial-pinned JTAG programmer with part/device guards |
| `fpga/bitstreams/vcu118_highmem_2026-09-24/` | Created (gitignored) | Archived .bit/.bin/.ltx out of the Bazel cache |
| `fpga/bitstreams/vcu118_highmem_2026-09-25/` | Created (gitignored) | Rebuild with all fixes + timing report |
| `notes2/fpga/vcu118_bitstream_debug.md` | Created | Detailed debug log for 5 bitstream build errors |
| Generated MIG IP (test_project) | In `~/workspace/test_project/` | Vivado block design (source for DCPs) |

### DCP Files — NOT for public commit

The DCP files (`fpga/ip/ddr4_vcu118/dcp/*.dcp`) contain pre-synthesized Xilinx IP netlists. Distributing them in a public repo likely violates the Xilinx/AMD EULA which grants a license to *use* IP on Xilinx FPGAs but restricts redistribution of IP in any form (including synthesized netlists). For public release, replace with an XCI-based flow or provide a generation script. DCPs can be committed to private/internal repos.

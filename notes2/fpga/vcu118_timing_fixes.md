# VCU118 — Timing Fixes: Handoff

Written 2026-10-06 for the agent picking this up.

**First read the "Working rules" section of `notes2/fpga/vcu118_uart_ila_debug.md`.** In short:
- Don't run Bazel or bitstream builds, and don't touch the board, without asking. Prepare the changes
  and give the user the commands.
- Verilator/RISC-V builds run inside the FHS shell; Vivado runs outside it.
- `bazelisk shutdown` when switching between the two, because the Bazel server keeps the environment
  it was started in.
- Always do the elab check before a 3.5 h bitstream build.
- Archive build outputs to `fpga/bitstreams/<name>/`.
- `/` is almost full (~0.4 GB free on 2026-10-06), so check `df -h /` before any build.

---

## Status (2026-10-07): DEFERRED

**Decision (user, 2026-10-07):** leave the remaining violations as they are for now and move on to
image tests. The latest build `fpga/bitstreams/vcu118_highmem_rom_2026-10-06_201108/` works on the
board (ROM boot, UART, `DDR PASS`).

Its timing: WNS −2.351 ns, 1538 failing endpoints. Issues 1 and 2 below are **fixed**. Three new or
remaining groups (A, B, C) are described in
[Results of the 2026-10-06 build](#results-of-the-2026-10-06-build), each with its planned fix.
When picking this up again, start there; everything below it describes the 2026-10-05 state.

## Status (2026-10-06, historical)

The ROM-boot bitstream works on the board (banner and `alive` heartbeat on `ttyUSB4`). Its timing
does **not** close, though. The reference build is `fpga/bitstreams/vcu118_highmem_rom_2026-10-05/`
(`chip_vcu118_timing_summary_routed.rpt`, `chip_vcu118_utilization_placed.rpt` and
`chip_vcu118_routed.dcp` are in that folder).

| # | Clock pair | WNS | Failing endpoints | Same in the 2026-09-29 build? | Priority |
|---|---|---|---|---|---|
| 1 | `clk_main` → `clk_main` (40 MHz, 25 ns) | **−0.347 ns** | 37 | No, that build was +0.603 ns (placement variation) | High |
| 2 | `mmcm_clkout0` → `mmcm_clkout0` (MIG UI clock, 300 MHz) | **−0.687 ns** | 58 (+7 pulse-width, −0.201 ns) | Yes, but smaller then (−0.206 ns) | High, before using DDR |
| 3 | `c0_sys_clk_p` → `mmcm_clkout0` / `mmcm_clkout6` | −1.673 / −0.967 ns | few | Yes (−1.49 / −0.92 ns); DDR calibration passed | Low |

The goal is to close all of them, so that the MobileNet demo can rely on DDR and on loading data
from the host into the TCMs.

---

## Issue 1 — `clk_main`: host bridge → 4 MB SRAM

**Worst path** (`chip_vcu118_timing_summary_routed.rpt`, first `clk_main` violation):

- **Source:** `i_coralnpu_soc/i_chisel_subsystem/rvv_core/hostBridge/read_addr_q_q/wrap_1_reg/C`
- **Destination:** `.../sram/sram/sramModules_291/mem_reg_0/ADDRARDADDR[6]`
- **Data path:** 25.128 ns = **2.637 ns logic + 22.491 ns routing**, 22 logic levels, clock skew 0.526 ns.
- **What it passes through:**
  1. the host bridge's read-address queue (a distributed RAM read);
  2. the crossbar's device select and arbitration (`lastGrant`, nets with fo=836 and fo=838);
  3. the `sram_socket` arbiter;
  4. the SRAM adapter's enable (`enable0581_out`, a single 3.86 ns route);
  5. the BRAM address pins.

  None of these stages has a register.

**Why the routing is so long:**
- The on-chip SRAM is 4 MB:
  - `hdl/chisel/src/soc/SoCChiselConfig.scala:265`: `TlulSramParameters(sramSizeBytes = 4 * 1024 * 1024, ...)`
  - `hdl/chisel/src/soc/CrossbarConfig.scala:118`: `AddressRange(0x20000000, 0x400000)`
- That's about 1000 RAMB36. Together with the 1 MB + 1 MB TCMs, the design uses 1561 of 2160 BRAMs.
- Per SLR, BRAM use is 71% / 84% / 61% (SLR0/1/2), so the SRAM has to span SLR boundaries.
- There are 5954 SLR1↔SLR2 crossings, and **none of them use the TX/RX Laguna registers**. That's
  expected, because the crossing nets are combinational.

**Options (ranked):**

1. **Shrink the SRAM for VCU118 builds.** This is the biggest lever. It frees about 700 BRAMs, the
   design fits in fewer SLRs, and every path gets shorter.
   - Make the size a parameter of the highmem/VCU118 subsystem only. Don't change the shared
     default: the cocotb tests use the SRAM (`tests/cocotb/tlul/test_tlul_to_sram.py`,
     `test_subsystem.py`, `coralnpu_xbar_test.py`, `test_dma_integration.py`, ...).
   - Both places above must agree: the size in `SoCChiselConfig` and the range in `CrossbarConfig`.
   - Check what uses `0x20000000` on the FPGA side: `fpga/sw/isp_cam_test.c` (camera, not used on
     VCU118) and `fpga/sw/dma_test.cc`. Grep linker scripts and `sw/` for anything larger.
   - **Ask the user how much SRAM the MobileNet plan needs** before choosing a size. Images and the
     model are expected to come from DDR or the TCMs.
   - The highmem subsystem target is `//fpga/ip/coralnpu_chisel_subsystem_highmem`.
2. **Add a register stage in front of the SRAM.** Put a TL-UL register slice between the crossbar's
   `sram` port and `TlulSram`, or register the address and enable inside `TlulSram` before the BRAMs.
   - This adds one cycle of latency on SRAM accesses.
   - It roughly halves the path no matter how it is placed, and it lets `phys_opt` use Laguna
     registers at the SLR crossings.
   - Run the cocotb SRAM/xbar tests afterwards (see Verification).
3. **Stopgap: lower `clk_main` to 35 MHz.**
   - Change `_VCU118_CLOCK_FREQUENCY_MHZ = "40"` at `fpga/BUILD:29`.
   - The MMCM output (`fpga/rtl/clkgen_xilultrascaleplus_vcu118.sv:51`) becomes 1200/34.25 ≈
     35.04 MHz. The clock table reports 35, and the 0.1% error doesn't matter for the UART.
   - The software reads the frequency from the clock table, so nothing else changes.
   - The path needs about 25.4 ns, so the maximum is about 39 MHz. This costs about 12% performance.
4. **Implementation settings only.** Try different placer and phys-opt directives (e.g. placer
   `SSI_*`, `phys_opt` `AggressiveExplore`), or `MAX_FANOUT` on the arbiter/adapter nets, in
   `fpga/vivado_setup_hooks.tcl` / `fpga/vivado_pre_opt_hooks_vcu118.tcl`. This might close
   −0.35 ns, but the result depends on placement luck (the same RTL passed by +0.6 ns last time).
   Don't rely on this alone.

**Recommended:** option 1 if the user doesn't need 4 MB, otherwise option 2. Use option 3 only if a
passing build is needed in the meantime.

---

## Issue 2 — MIG UI clock (300 MHz): DDR response path

**Worst path:**

- **Source:** `.../ddr_mem_axi_conv/TlulIdRemapper/io_tl_d_out_q/wrap_1_reg/C`
- **Destination:** `.../xbar/deviceInterfaces_ddr_mem_fifo/rsp_queue/source/mem_3_data_reg[111]/D`
- **Data path:** 3.806 ns = 0.829 ns logic + 2.977 ns routing, against a 3.333 ns period.
- 8 levels (LUT3, 2× LUT6, 2× MUXF7, 2× MUXF8, RAMD32): a distributed-RAM queue read followed by
  a wide multiplexer.

**Cause:** general Chisel bus logic is clocked at the MIG's 300 MHz UI clock.
- `fpga/rtl/chip_vcu118.sv:380` drives `.ddr_clk_i(c0_ddr4_ui_clk)`.
- `fpga/rtl/coralnpu_soc.sv:694` passes it on as `io_async_ports_devices_ddr_clock`.
- The DDR side of the subsystem's clock-domain crossing therefore runs at 300 MHz.

**Fix: run the subsystem's DDR side at a slower clock (100–150 MHz) and let the SmartConnect do
the clock conversion.**
- The DDR block design (`ddr_system_bd`) has a SmartConnect with a single clock, `aclk` =
  `c0_ddr4_ui_clk` (`fpga/ip/ddr4_vcu118/GENERATING_DDR4_IP.md`, step 3).
- Set `CONFIG.NUM_CLKS 2` on the SmartConnect:
  - its S00 side on the new, slower clock (`aclk1`);
  - its M00 (MIG) side stays on the UI clock.
- Clock source for the S00 side: the MIG's `addn_ui_clkout1` (currently unconnected in
  `chip_vcu118.sv:239`; set it to 100 or 150 MHz in the MIG configuration), or `clk_main`. Using
  `addn_ui_clkout1` keeps the DDR side independent of `clk_main` changes.
- Bring the new clock and a matching synchronous reset out of the block design, and connect them to
  `ddr_clk_i` / `ddr_rst` in `chip_vcu118.sv`. The subsystem's own crossing stays as it is; only
  its DDR-side clock gets slower.
- Regenerate the two pre-synthesised checkpoints (`fpga/ip/ddr4_vcu118/dcp/ddr_system_bd_*`) and
  the `.xci` files following `GENERATING_DDR4_IP.md`. Then update `rtl/ddr_system_bd.v` /
  `ddr_system_bd_wrapper.v` for the new ports.
- **Bandwidth check:** 256 bits at 150 MHz ≈ 4.8 GB/s, still far above the core side (128 bits at
  40 MHz ≈ 0.64 GB/s).
- Add the new clock to the XDC only if Vivado doesn't derive it automatically. MMCM outputs inside
  the MIG IP are normally derived.

This also removes the 7 pulse-width failures, if they are on Chisel cells. Confirm in the
pulse-width section of the timing report.

---

## Issue 3 — MIG-internal reset synchroniser (low priority)

- **Paths:**
  - `i_ddr4/ddr_system_bd_i/ddr4_0/inst/u_ddr4_infrastructure/rst_async_riu_div_reg` →
    `rst_div_sync_r_reg[0]`: −1.673 ns, `c0_sys_clk_p` → `mmcm_clkout0`.
  - Same source → `rst_riu_sync_r_reg[0]`: −0.967 ns, to `mmcm_clkout6`.
- Both end at the first flop of a reset synchroniser. This was present in the previous build too,
  and DDR calibration passed (`fpga/bitstreams/vcu118_highmem_rom_2026-09-29/ddr_check_2026-10-05.txt`).
- First check whether the MIG's own constraints (`fpga/ip/ddr4_vcu118/xdc/ddr_system_bd_ddr4_0_0.xdc`)
  are applied to the reset synchroniser in our flow. Only if they're missing, add a targeted
  `set_false_path -to` on those `*_sync_r_reg[0]` D pins.
- Don't add broad false paths between the clocks.

---

## Progress (2026-10-06)

- **Issue 1, option 3 done:** `fpga/BUILD` now sets `_VCU118_CLOCK_FREQUENCY_MHZ = "35"` (35.04 MHz).
  Options 1/2 are still open.
- **Issue 2, RTL and block design done:**
  - The MIG already produces `addn_ui_clkout1` at 100 MHz, and the wrapper already has the
    port, so the MIG configuration and the wrapper ports don't change.
  - `chip_vcu118.sv` now drives `ddr_clk_i` from `addn_ui_clkout1_0`, with a reset synchroniser
    (`ddr_axi_rst`).
  - `GENERATING_DDR4_IP.md` steps 3/4 describe the two-clock SmartConnect.
  - Block design regenerated in `~/workspace/test_project` (2026-10-06). The new SmartConnect
    checkpoint (with `aclk1`) and `rtl/ddr_system_bd.v` are copied into the repo.
  - Second regeneration (12:51): the SmartConnect address segment was widened from 512 MB to
    2 GB at `0x80000000`, to match the SoC's `ddr_mem` window and the 2 GB MIG
    (`C_SEG_SIZE_ARRAY` 29 → 31). The 11:29 SmartConnect checkpoint is backed up as
    `..._2026-10-06_1129_512M.dcp`.
  - The MIG checkpoint was not regenerated: Vivado reused its 2026-09-22 cached build, so the
    configuration is unchanged.
  - The old checkpoints are backed up in
    `fpga/bitstreams/vcu118_highmem_rom_2026-10-05/ddr4_dcp_backup_2026-09-22/`.
  - Don't copy the regenerated MIG constraints file: the repo copy renames `c0_ddr4_dm_dbi_n`
    to `c0_ddr4_dm_n` by hand.
  - No XDC change expected: `-include_generated_clocks c0_sys_clk_p` covers the new clock.

## Results of the 2026-10-06 build

Build: `fpga/bitstreams/vcu118_highmem_rom_2026-10-06_201108/`. It contains:
- 35 MHz `clk_main`;
- the DDR side on the 100 MHz `addn_ui_clkout1`;
- the 2 GB SmartConnect segment;
- the ROM DDR test.

DDR test passed on the board.

| Clock pair | 2026-10-05 | 2026-10-06 |
|---|---|---|
| `clk_main → clk_main` (Issue 1) | −0.347 ns, 37 EPs | **+2.200 ns, clean** |
| SoC DDR side (Issue 2), now `mmcm_clkout1` 100 MHz | −0.687 ns at 300 MHz | **+3.847 ns, clean** |
| `clk_main ↔ clk_aon / clk_spim_unbuf` (A) | clean | **−2.351 ns, 791 EPs** (new) |
| `mmcm_clkout0 → mmcm_clkout0` 300 MHz (B) | −0.687 ns, 58 EPs | **−1.715 ns, 708 EPs** + 2 pulse-width (−0.052 ns) |
| `c0_sys_clk_p → mmcm_clkout0 / 6` (C = Issue 3) | −1.673 / −0.967 ns | −1.224 / −0.656 ns, 3 EPs |

The placer reports "highly congested", mostly in SLR0/SLR1, as it did in the 2026-10-05 build.
BRAM use per SLR is 71% / 62% / 84% (SLR0/1/2).

### A. CDC paths between `clk_main` and `clk_aon` / `clk_spim_unbuf` (caused by the 35 MHz change)

**What fails:**
- 200 + 352 endpoints between `clk_main` and `clk_aon`, and 112 + 127 between `clk_main` and
  `clk_spim_unbuf`.
- Every reported path ends in a Chisel async FIFO sink register
  (`.../sink/io_deq_bits_deq_bits_reg/cdc_reg_reg`). They are in the ISP FIFOs (`ispyocto_ctrl`,
  `ispyocto_m1/m2`) and in the `spi_master` and `spi_master_flash` FIFOs.
- `clk_aon` (CLKOUT4, 10 MHz) is the ISP clock despite its name.

**Why:**
- All three clocks come from the same MMCM, so Vivado times the crossings as synchronous.
- At 40 MHz (25 ns) against 10 and 100 MHz, the edges are always at least 5 ns apart, so the paths
  passed.
- At 35.036 MHz (28.542 ns) the edges come within 0.208 ns of each other, which becomes the
  requirement. That requirement means nothing for an async FIFO.
- No whole-number MHz between 25 and 40 gives clean ratios: 30 MHz leaves 3.3 ns, and 33 MHz rounds
  to a non-integer divider. So the fix is a constraint, not another frequency.

**Functional impact now:** probably none. The FIFOs are designed for unrelated clocks, the ISP is
unused, and the SPI masters aren't used by the demo. This is not yet proven: run step 1 below first.

**Fix (XDC only, no RTL):**
1. Check that every crossing is synchronised. You run this on the routed checkpoint, outside FHS,
   with about 20 GB of RAM:
   ```tcl
   open_checkpoint fpga/bitstreams/vcu118_highmem_rom_2026-10-06_201108/chip_vcu118_routed.dcp
   report_cdc -from [get_clocks clk_main] -to [get_clocks {clk_aon clk_spim_unbuf}] -details -file cdc_main_to_x.rpt
   report_cdc -from [get_clocks {clk_aon clk_spim_unbuf}] -to [get_clocks clk_main] -details -file cdc_x_to_main.rpt
   ```
   Go on only if neither report shows "Unsafe" or "Unknown" crossings.
2. Add to `fpga/pins_vcu118.xdc`:
   ```tcl
   # clk_main, clk_aon and clk_spim_unbuf share the MMCM, but at 35 MHz their edges have no useful
   # alignment. All crossings go through Chisel async FIFOs; bound the data path only.
   set_max_delay -datapath_only 10.0 -from [get_clocks clk_main] -to [get_clocks {clk_aon clk_spim_unbuf}]
   set_max_delay -datapath_only 10.0 -from [get_clocks {clk_aon clk_spim_unbuf}] -to [get_clocks clk_main]
   ```
   Prefer this to `set_clock_groups -asynchronous`, because it still bounds the async FIFO data path.

### B. 300 MHz MIG UI domain: SmartConnect MI side and MIG `u_ddr_ui`

**What fails:**
- The worst path is `smartconnect_0/.../s00_w_node/inst_mi_handler/...inst_rd_addrb/count_r_reg` →
  `...doutb_reg_reg[41]` (distributed-RAM FIFO read).
- Data path 4.845 ns against 3.333 ns, 95% of it routing.
- One net between neighbouring slices (X108Y877 → X109Y877) takes 2.8 ns.
- Other failing paths start at the SmartConnect reset fan-out (`clk_map/psr_aclk`) or are in the
  MIG's `u_ddr_ui`.

**Why:** Issue 2 moved the SoC logic off 300 MHz, but the SmartConnect's MIG side (512 bits, now
with a 3:1 clock-conversion FIFO) and the MIG UI remain at 300 MHz. In a congested design they
don't place and route well enough.

**Functional impact now:** the DDR test passed, but this is on the DDR data path and could fail
intermittently. If image data from DDR ever looks corrupted, suspect this first.

**Fixes, in order:**
1. **Shrink the 4 MB SRAM for VCU118** (Issue 1, option 1 above). This frees ~700 RAMB36 and eases
   congestion everywhere. It needs the user to decide how much SRAM MobileNet needs.
2. **Run DDR4 at 1600 instead of 2400.** This regenerates the MIG with a 1250 ps memory clock
   period, which gives a 200 MHz UI clock (5 ns). Bandwidth is still far above what the core uses.
   On its own this is borderline, since the worst path needs ~4.85 ns. After regenerating, check
   that `addn_ui_clkout1` is still 100 MHz.
3. Optional: a pblock that keeps the SmartConnect and the MIG UI logic next to the DDR4 C1 banks in
   SLR2.

### C. MIG reset synchroniser (Issue 3)

Unchanged; the plan in Issue 3 above still applies. Low priority.

### Next build when this resumes

Do A (XDC) and B.1 (SRAM shrink) together, so one build covers both, then re-check B before
deciding on B.2.

## Suggested order (2026-10-06, historical)

1. Ask the user how much SRAM they need. That decides option 1 vs 2 for Issue 1.
2. Make the Issue 2 change (DDR clock) and the Issue 1 change together, so one 3.5 h build covers
   both.
3. Check Issue 3 constraints in the same build if it's cheap. Otherwise leave it.

## Verification

- **Chisel/RTL changes:** run the existing tests inside FHS (the user runs them):
  - `bazel test //hdl/chisel/src/soc/...` (or the relevant targets);
  - the cocotb tests that use the SRAM, e.g. `//tests/cocotb/tlul:...`.
- **Verilator ROM sim:** check that it still prints the banner and `alive 0x00000000`. One instance
  only; it is slow (one heartbeat = 50 M cycles).
- **Elab check:** `bazelisk build //fpga:build_chip_vcu118_elab_only_highmem_rom`. Watch for new
  `Synth 8-3848` (undriven net) warnings outside the ISP.
- **Bitstream:** `bazelisk run //fpga:archive_chip_vcu118_bitstream_highmem_rom`. This builds the
  bitstream if needed and copies it, with its reports, to
  `fpga/bitstreams/vcu118_highmem_rom_<build time>/`.
- **Acceptance criteria:**
  - `Timing constraints are met` in `chip_vcu118_timing_summary_routed.rpt`, or only Issue 3
    remains and is explained.
  - Board: `ttyUSB4` shows the banner and the heartbeat, at the new frequency if it changed.
  - `fpga/check_ddr_vcu118.tcl` with the new `.ltx` shows `CAL PASS`.
  - Ideally, a DDR read/write test from the core, since nothing has tested DDR end-to-end yet.
- **Optional:** run `fpga/inspect_routed_dcp.tcl` on the new routed checkpoint. Section 1 should
  show `state_q_reg` cells under `i_autoboot`.

## Useful queries on the report

```bash
R=fpga/bitstreams/vcu118_highmem_rom_2026-10-05/chip_vcu118_timing_summary_routed.rpt
# Worst slack per clock pair
awk '/^From Clock:/{f=$3} /^  To Clock:/{t=$3} /^Slack \(VIOLATED\)/{if(!seen[f" "t]++)print f" -> "t": "$4}' $R
# BRAM per SLR
awk '/^14. SLR CLB Logic/{c++} c==2' fpga/bitstreams/vcu118_highmem_rom_2026-10-05/chip_vcu118_utilization_placed.rpt | grep -E "CLB LUTs|Block RAM Tile"
```

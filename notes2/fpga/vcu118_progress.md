# VCU118 Port — Progress Log

## Status: Phases 1-6c DONE — Bitstream Generated, Ready for Board Bring-Up

Last updated: 2026-09-25

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
- Reset is active HIGH per board.xml (rst_polarity=1); `chip_vcu118.sv` inverts at the pad.

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

**Known warnings (non-blocking)**:
- `[Timing 38-282]` — timing violations present. Needs investigation during bring-up. May need clock frequency reduction or additional timing constraints.
- `[Constraints 18-4427]` — DCP property overrides (cosmetic, inherent to DCP flow)
- `[Vivado 12-4739]` — MIG internal hierarchy paths not found (DCP flow, constraints apply to flattened netlist)
- `[Project 1-840]` — DCP used instead of XCI (expected)

**Bitstream location**: In Bazel cache under:
```
~/.cache/bazel/_bazel_garvit/<hash>/execroot/coralnpu_hw/bazel-out/k8-fastbuild/bin/fpga/build.build_chip_vcu118_bitstream_highmem/
```

---

## Remaining Work

### Phase 7: Board Bring-Up — next step

1. Program FPGA via Vivado JTAG
2. Verify LEDs (halted/fault/DDR cal)
3. UART echo test (115200 baud on USB-UART)
4. SPI program loading via FTDI adapter
5. DDR4 read/write test
6. JTAG debug (OpenOCD → RISC-V debug module)

### Phase 8: MobileNet Demo — after bring-up

Build MobileNet v1 binary with TFLite Micro for highmem variant. Embed sample images as C arrays. Load → run → print classification on UART.

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
| "GPIO on DIP switches" | DIP switches in HP banks, incompatible with LVCMOS12 | GPIO removed, tied off internally |

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
| `notes2/fpga/vcu118_bitstream_debug.md` | Created | Detailed debug log for 5 bitstream build errors |
| Generated MIG IP (test_project) | In `~/workspace/test_project/` | Vivado block design (source for DCPs) |

### DCP Files — NOT for public commit

The DCP files (`fpga/ip/ddr4_vcu118/dcp/*.dcp`) contain pre-synthesized Xilinx IP netlists. Distributing them in a public repo likely violates the Xilinx/AMD EULA which grants a license to *use* IP on Xilinx FPGAs but restricts redistribution of IP in any form (including synthesized netlists). For public release, replace with an XCI-based flow or provide a generation script. DCPs can be committed to private/internal repos.

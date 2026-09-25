# VCU118 Bitstream Build — Debug Log

## Error: 118 missing pin assignments (2026-09-23)

**Command**: `bazel build //fpga:build_chip_vcu118_bitstream_highmem`

**Stage**: Implementation (`impl_1`), during pre-optimization hooks (`vivado_pre_opt_hooks.tcl`)

**Error message**:
```
ERROR: 118 top-level ports are missing physical pin assignments!
Build failed due to missing pin assignments.
sourcing script .../vivado_pre_opt_hooks.tcl failed
ERROR: [Vivado 12-13638] Failed runs(s) : 'impl_1'
```

All 118 missing ports were DDR4 signals: `c0_ddr4_act_n`, `c0_ddr4_adr[0..16]`, `c0_ddr4_ba[0..1]`, `c0_ddr4_bg[0..1]`, `c0_ddr4_dq[0..63]`, `c0_ddr4_dqs_t/c[0..7]`, `c0_ddr4_dm_n[0..7]`, `c0_ddr4_ck_t/c`, `c0_ddr4_cke`, `c0_ddr4_odt`, `c0_ddr4_cs_n`, `c0_ddr4_reset_n`, `c0_sys_clk_p/n`.

---

### Root Cause Analysis

**Three independent issues combined to cause the failure:**

#### 1. Board XDC requires `BOARD_PART` (missing in FuseSoC flow)

The MIG-generated `ddr_system_bd_ddr4_0_0_board.xdc` uses `BOARD_PART_PIN` properties:
```tcl
set_property BOARD_PART_PIN {c1_ddr4_act_n} [get_ports c0_ddr4_act_n]
set_property BOARD_PART_PIN {c1_ddr4_adr0}  [get_ports c0_ddr4_adr[0]]
...
```

These resolve to `PACKAGE_PIN` only when `BOARD_PART` is set on the Vivado project (e.g. `xilinx.com:vcu118:part0:2.3`). FuseSoC creates a project with only the FPGA part (`xcvu9p-flga2104-2L-e`), not the board part. Without `BOARD_PART`, all `BOARD_PART_PIN` constraints silently fail → no pin locations applied.

This produced the 168 critical warnings:
```
CRITICAL WARNING: [Constraints 18-638] Undefined BOARD_PART property for current project
while applying board-derived constraints.
```

**Why not just set `BOARD_PART`?** The VCU118 board files ARE installed in Vivado 2025.2 — but at a non-standard location (`/opt/Xilinx/2025.2/2025.2/data/xhub/boards/XilinxBoardStore/boards/Xilinx/vcu118/`), moved from the old `data/boards/board_files/` path. Setting `BOARD_PART` in the FuseSoC project (`xilinx.com:vcu118:part0:2.4`) would likely work, but the explicit `PACKAGE_PIN` approach is more robust: no dependency on board file installation paths (which differ between Vivado versions), no `BOARD_PART_PIN` indirection, and the constraints are self-documenting. Pin locations verified identical between board XML v2.3 (2019.2) and v2.4 (2025.2) — all 115 DDR4 C1 pins match.

**Alternative fix (not used)**: Add `set_property BOARD_PART xilinx.com:vcu118:part0:2.4 [current_project]` to the setup Tcl. This would make the `_board.xdc` work but couples the build to board file availability and version.

#### 2. Port naming mismatch (`dm_dbi_n` vs `dm_n`)

The MIG IP's internal port is `c0_ddr4_dm_dbi_n[7:0]`, but the block design wrapper renames it:

```
MIG internal:     c0_ddr4_dm_dbi_n[7:0]
  ↓ (block design netlist ddr_system_bd.v)
Wrapper port:     C0_DDR4_0_dm_n[7:0]
  ↓ (chip_vcu118.sv)
Top-level port:   c0_ddr4_dm_n[7:0]
```

The MIG XDC (`ddr_system_bd_ddr4_0_0.xdc`) references the internal name:
```tcl
set_property OUTPUT_IMPEDANCE RDRV_40_40 [get_ports "c0_ddr4_dm_dbi_n[5]"]
set_property IOSTANDARD POD12_DCI       [get_ports "c0_ddr4_dm_dbi_n[5]"]
```

These `get_ports` calls fail silently because the top-level ports are named `c0_ddr4_dm_n`, not `c0_ddr4_dm_dbi_n`. The affected constraints are OUTPUT_IMPEDANCE, IOSTANDARD, and the `interface` grouping — 23 references total.

#### 3. Wrong pre-optimization hooks sourced

`vivado_setup_hooks.tcl` hardcoded the Nexus hooks path:
```tcl
set_property STEPS.OPT_DESIGN.TCL.PRE "${workroot}/vivado_pre_opt_hooks.tcl" [get_runs impl_1]
```

For VCU118 builds, the correct file is `vivado_pre_opt_hooks_vcu118.tcl` (which skips ISP and DDR pblock scripts that don't exist for VCU118). The Nexus version tries to source `pblock_u_isp.tcl` and `pblock_u_ddr.tcl` — these files aren't in the VCU118 build tree and cause the sourcing to fail.

#### 4. `bg[1]` — no physical pin on VCU118

The VCU118 DDR4 uses MT40A256M16LY-062E (4Gb ×16), which has only 1 bank group (`BG0`). The board XML has a single `c1_ddr4_bg` pin (H13).

However, the MIG block design wrapper exposes `bg[1:0]` (2 bits). In the netlist (`ddr_system_bd.v`), only `bg[0]` is connected to the MIG instance:
```verilog
output [1:0]C0_DDR4_0_bg;       // declared 2-bit
    .c0_ddr4_bg(C0_DDR4_0_bg[0]),  // only [0] connected
```

`bg[1]` is undriven and has no physical pin — it cannot be assigned a `PACKAGE_PIN`. Vivado synthesizes it as a top-level port (constant 0 output), and the pin check script correctly flags it as unassigned.

---

### Fixes Applied

#### Fix 1: Explicit pin assignment XDC

Created `fpga/ip/ddr4_vcu118/xdc/ddr4_vcu118_pins.xdc` with 116 explicit `PACKAGE_PIN` assignments extracted from the VCU118 board XML (`part0_pins.xml`, board rev 2.3 at `/opt/Xilinx/Vivado/2019.2/data/boards/board_files/vcu118/2.3/`).

This replaces the `_board.xdc` entirely — no dependency on `BOARD_PART` or installed board files.

**FuseSoC core file** (`ddr4_vcu118.core`): changed from:
```yaml
- xdc/ddr_system_bd_ddr4_0_0_board.xdc: { file_type: user, copyto: ... }
```
to:
```yaml
- xdc/ddr4_vcu118_pins.xdc: { file_type: xdc }
```

**Setup Tcl** (`vivado_ddr4_vcu118_setup.tcl`): removed `add_files` for the `_board.xdc`.

#### Fix 2: Rename `dm_dbi_n` → `dm_n` in MIG XDC

In `fpga/ip/ddr4_vcu118/xdc/ddr_system_bd_ddr4_0_0.xdc`, replaced all 23 instances of `c0_ddr4_dm_dbi_n` with `c0_ddr4_dm_n` to match the top-level port names.

#### Fix 3: Board-aware pre-opt hooks

In `fpga/vivado_setup_hooks.tcl`, changed from hardcoded path to conditional:
```tcl
if {[file exists "${workroot}/vivado_pre_opt_hooks_vcu118.tcl"]} {
    set_property STEPS.OPT_DESIGN.TCL.PRE "${workroot}/vivado_pre_opt_hooks_vcu118.tcl" [get_runs impl_1]
} else {
    set_property STEPS.OPT_DESIGN.TCL.PRE "${workroot}/vivado_pre_opt_hooks.tcl" [get_runs impl_1]
}
```

#### Fix 4: Remove `bg[1]` from top-level

In `fpga/rtl/chip_vcu118.sv`:
- Top-level port: `output logic [1:0] c0_ddr4_bg` → `output logic [0:0] c0_ddr4_bg`
- Added internal wire for wrapper connection:
  ```systemverilog
  wire [1:0] c0_ddr4_bg_internal;
  assign c0_ddr4_bg = c0_ddr4_bg_internal[0];
  ```
- Wrapper instantiation: `.C0_DDR4_0_bg(c0_ddr4_bg)` → `.C0_DDR4_0_bg(c0_ddr4_bg_internal)`

---

### Files Modified

| File | Change |
|---|---|
| `fpga/ip/ddr4_vcu118/xdc/ddr4_vcu118_pins.xdc` | **New** — 116 explicit PACKAGE_PIN constraints |
| `fpga/ip/ddr4_vcu118/xdc/ddr_system_bd_ddr4_0_0.xdc` | `dm_dbi_n` → `dm_n` (23 occurrences) |
| `fpga/ip/ddr4_vcu118/ddr4_vcu118.core` | Replaced `_board.xdc` with `ddr4_vcu118_pins.xdc` |
| `fpga/ip/ddr4_vcu118/vivado_ddr4_vcu118_setup.tcl` | Removed `_board.xdc` loading |
| `fpga/vivado_setup_hooks.tcl` | Board-aware pre-opt hooks selection |
| `fpga/rtl/chip_vcu118.sv` | `bg[1:0]` → `bg[0:0]` with internal wire |

---

## Error 2: LVCMOS12 incompatible with HP banks (2026-09-23)

**Stage**: Implementation (`impl_1`), DRC check

**Error message**:
```
ERROR: [DRC BIVB-1] Bank IO standard Vcc: Conflict ... LVCMOS12 ... HP bank 72/73
```

### Root Cause

GPIO pins (DIP switches at B17, G16, J16, D21) are in HP (High Performance) I/O banks 72 and 73. HP banks on UltraScale+ do not support LVCMOS12 — they require 1.0V–1.8V SSTL/POD/HSTL standards.

### Fix Applied

Removed GPIO from top-level ports entirely. GPIO is not needed for the MobileNet demo — DIP switches are not part of the datapath.

**Files modified:**
| File | Change |
|---|---|
| `fpga/rtl/chip_vcu118.sv` | Removed `gpio` from port list, tied off `gpio_in = 8'b0` internally |
| `fpga/pins_vcu118.xdc` | Removed GPIO pin constraints, added comment explaining why |

---

## Error 3: Clock placement failure — non-GCIO pins driving BUFGs (2026-09-23)

**Stage**: Implementation (`impl_1`), placement (Place 30-675)

**Error message**:
```
ERROR: [Place 30-675] Sub-optimal placement for a global clock-capable IO pin and BUFG pair.
```

Two signals affected:
- `spi_clk_i` — SPI slave clock on PMOD1 pin N28 (Bank 47)
- `tck_i` — JTAG TCK on PMOD0 pin AY14 (Bank 67)

### Root Cause

Both clocks enter through PMOD pins, which are general-purpose I/O — not GCIO (Global Clock-Capable IO) pins. Vivado infers BUFGCEs for clock signals, but BUFGCEs must be driven from GCIO pins for dedicated clock routing. PMOD pins lack the direct connection to clock routing resources.

### Fix Applied

Added `CLOCK_DEDICATED_ROUTE FALSE` constraints to allow fabric routing for these clocks:
```xdc
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets tck_i_IBUF_inst/O]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets spi_clk_i_IBUF_inst/O]
```

This is safe because both are low-speed clocks (JTAG TCK ~500 kHz, SPI slave ~12 MHz) where fabric routing jitter is negligible. The Nexus board uses the same pattern for `ISP_DVP_PCLK`.

**Files modified:**
| File | Change |
|---|---|
| `fpga/pins_vcu118.xdc` | Added `CLOCK_DEDICATED_ROUTE FALSE` for `tck_i` and `spi_clk_i` |

---

## Error 4: MMCM CLKFBOUT_MULT_F granularity (2026-09-24)

**Stage**: Implementation (`impl_1`), `write_bitstream` DRC check

**Error message**:
```
ERROR: [DRC AVAL-168] MMCM_ADV Phase shift and divide attr checks: The MMCME4_ADV
cell i_clkgen/i_clkgen/pll has a fractional CLKFBOUT_MULT_F value (9.600) which is
not a multiple of the hardware granularity (0.125) and will be adjusted to the nearest
supportable value. Please update the design to use a valid value.
```

Also present (non-blocking but concerning):
```
CRITICAL WARNING: [Timing 38-282] The design failed to meet the timing requirements.
```

### Root Cause

The VCU118 uses a 125 MHz input clock (vs 100 MHz on Nexus). To reach the same 1200 MHz VCO, the multiplier was set to 9.600 (125 × 9.6 = 1200). However, MMCME4_ADV requires `CLKFBOUT_MULT_F` to be a multiple of 0.125, and 9.600 / 0.125 = 76.8 — not an integer.

The Nexus value of 12.000 works because 12.0 / 0.125 = 96 (integer).

The VCU118 clkgen also used `MMCME2_ADV` (copied from Nexus). Vivado silently maps this to `MMCME4_ADV` on UltraScale+, but the MMCME4 granularity rules apply and catch the invalid value at the `write_bitstream` DRC stage.

**Why 1200 MHz VCO matters**: all downstream dividers are shared and assume 1200 MHz:
- CLKOUT0: `1200 / ClockFrequencyMhz` → 50 MHz core clock (default)
- CLKOUT2: `1200 / 12` = 100 MHz SPI master clock
- CLKOUT4: `1200 / 120` = 10 MHz AON clock

### Fix Applied

Used `DIVCLK_DIVIDE` to bring the 125 MHz input to 25 MHz before multiplying:

```
VCO = (CLKIN / DIVCLK_DIVIDE) × CLKFBOUT_MULT_F
    = (125 / 5) × 48.0
    = 25 × 48 = 1200 MHz (exact)
```

48.000 / 0.125 = 384 (integer) — valid granularity. PFD frequency = 125 / 5 = 25 MHz (within 10–500 MHz range). All downstream dividers unchanged.

**Files modified:**
| File | Change |
|---|---|
| `fpga/rtl/clkgen_xilultrascaleplus_vcu118.sv` | `DIVCLK_DIVIDE` 1→5, `CLKFBOUT_MULT_F` 9.600→48.000 |
| `fpga/pins_vcu118.xdc` | Updated comment to reflect new clkgen parameters |

---

## Error 5: Post-bitstream hook references Nexus filenames (2026-09-24)

**Stage**: Implementation (`impl_1`), `write_bitstream` TCL.POST hook

**Error message**:
```
ERROR: [Bitstream 40-47] File ./chip_nexus.bit does not exist.
ERROR: [Writecfgmem 68-7] Could not load bitfile ./chip_nexus.bit.
ERROR: [Common 17-39] 'write_cfgmem' failed due to earlier errors.
```

Note: `write_bitstream` itself **succeeded** — `chip_vcu118.bit` and `chip_vcu118.bin` were generated. The failure was in the post-bitstream hook that runs after.

### Root Cause

`vivado_ddr4_vcu118_setup.tcl` (lines 36-38) registered `vivado_hook_write_bitstream_post.tcl` as a `STEPS.WRITE_BITSTREAM.TCL.POST` hook whenever the DDR4 DCPs were loaded and the hook file existed in the build directory.

This hook is designed for the **Nexus** flow — it stitches DDR4 calibration firmware (`calibration_ddr.elf`) into MIG BRAMs using `updatemem`, then converts the bitstream to BIN format via `write_cfgmem`. It has hardcoded references to `chip_nexus.bit`.

Two problems:
1. The hook references `chip_nexus.bit` — the VCU118 build produces `chip_vcu118.bit`
2. The hook expects `calibration_ddr.elf` — this doesn't exist for VCU118 because the DCP already has calibration firmware baked in

The hook file was also unnecessarily included in `chip_vcu118.core` (copied from `chip_nexus.core`), causing it to be present in the build directory and pass the `file exists` check.

### Fix Applied

1. Removed the hook registration from `vivado_ddr4_vcu118_setup.tcl` — replaced with a comment explaining that VCU118 DCPs include calibration firmware pre-stitched
2. Removed `vivado_hook_write_bitstream_post.tcl` from `chip_vcu118.core` file list — no need to copy it into the VCU118 build

**Files modified:**
| File | Change |
|---|---|
| `fpga/ip/ddr4_vcu118/vivado_ddr4_vcu118_setup.tcl` | Removed `STEPS.WRITE_BITSTREAM.TCL.POST` registration |
| `fpga/chip_vcu118.core` | Removed `vivado_hook_write_bitstream_post.tcl` from files_tcl |

---

### Lessons Learned

1. **FuseSoC projects don't set `BOARD_PART`** — any XDC using `BOARD_PART_PIN` or `get_board_part_interfaces` will silently fail. Always use explicit `PACKAGE_PIN` assignments.

2. **MIG wrapper renames ports** — the block design wrapper (`ddr_system_bd.v`) maps internal MIG ports to external names. The generated XDCs reference internal names. When integrating outside the block design context, all port name references in XDCs must be updated to match the actual top-level port names.

3. **Board-specific hooks need board-specific selection** — shared Tcl scripts that reference board-specific files (pblocks, hooks) should use conditional logic to pick the right variant.

4. **MIG exposes unused ports** — the wrapper may declare wider buses than the actual memory requires (e.g. `bg[1:0]` for single-BG memory). These undriven bits become top-level ports that need either physical pins or removal from the port list.

5. **HP banks don't support LVCMOS12** — UltraScale+ HP I/O banks only support 1.0V–1.8V standards (SSTL, POD, HSTL). When remapping pins between boards, check whether the target bank is HP or HR before assigning LVCMOS I/O standards.

6. **PMOD pins are not clock-capable** — GCIO pins are required for dedicated clock routing to BUFGs. Low-speed clocks on PMOD pins need `CLOCK_DEDICATED_ROUTE FALSE` to allow fabric routing.

7. **MMCM multiplier granularity differs by primitive** — MMCME4_ADV (UltraScale+) requires `CLKFBOUT_MULT_F` to be a multiple of 0.125. When changing input clock frequency, use `DIVCLK_DIVIDE` to reach a sub-frequency that multiplies cleanly to the target VCO, rather than relying on a fractional multiplier.

8. **Don't copy board-specific hooks between targets** — when porting a FuseSoC `.core` file to a new board, audit every file in the `files_tcl` section. Post-bitstream hooks with hardcoded filenames or board-specific assumptions will silently break the new target's build.

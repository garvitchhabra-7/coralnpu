# ASIC Verilog Generation for RvvCoreMiniAxi (GF22 TUD)

## RTL Variant

**Target:** `RvvCoreMiniAxi` — full RVV vector extension + scalar + float, 8KB ITCM / 32KB DTCM, AXI4 interface.

## Single-File RTL (Synthesis)

Use the dedicated synthesis target — it strips `bind` statements from the emitted SystemVerilog that Genus cannot parse. The standard `_cc_library` target keeps FIRRTL verification layers (which emit `bind`) enabled for simulation.

```bash
bazel build //hdl/chisel/src/coralnpu:rvv_core_mini_axi_synthesis
```

Output:
```
bazel-bin/hdl/chisel/src/coralnpu/RvvCoreMiniAxi_synth.sv
```

This file is fully self-contained — firtool inlines all blackbox modules (Sram, ClockGate, all RVV RTL) into the single emitted file. No additional Verilog files are needed for synthesis.

> **Do not use** `rvv_core_mini_axi_cc_library_emit_verilog` for synthesis — it emits `bind` blocks for SVA verification layers that Genus rejects with `VLOGPT-1` parse errors.

The synthesis genrule is defined at `hdl/chisel/src/coralnpu/BUILD:799`. It runs a Python post-processing step that strips all `bind` statements from the emitted SV via regex.

## Split-File RTL (One File per Module)

The Chisel emitter also produces `RvvCoreMiniAxi.zip` containing one `.sv` per module (~200 files). This is useful for tools that prefer per-module files or for cleaner error messages.

```bash
bazel build //hdl/chisel/src/coralnpu:rvv_core_mini_axi_split_synthesis_filelist
```

Output:
```
bazel-bin/hdl/chisel/src/coralnpu/filelist_synth.f
bazel-bin/hdl/chisel/src/coralnpu/RvvCoreMiniAxi.zip
```

The genrule (`hdl/chisel/src/coralnpu/BUILD:783`) reads `filelist.f` from the zip and filters out `verification/` entries that contain `bind` statements.

### Workflow

1. Unzip `RvvCoreMiniAxi.zip` to your synthesis working directory
2. Pass the filtered filelist to Genus:
```tcl
read_hdl -sv -define {GF22_TUD VLEN_128 ZVE32F_ON} -f filelist_synth.f
```

> The zip's `filelist.f` includes `verification/assert/*.sv` files which contain `bind` statements Genus cannot parse. `filelist_synth.f` is a filtered version with those entries removed. The module `.sv` files themselves are clean — bind statements only live in the `verification/` subdirectory.

## Technology-Specific Cells

Two types of technology cells are instantiated, both selected via preprocessor defines.

### SRAM Macros (TCM)

Defined in `hdl/verilog/Sram.v` under the `` `elsif GF22_TUD`` block (line 114). Two sizes, both 128-bit wide with 128-bit bit-write-enable (`WEM`):

| Size | Depth | Used for | Module Name |
|---|---|---|---|
| 512 x 128 | 512 | ITCM (8KB) | `GF22_TUD_512x128` |
| 2048 x 128 | 2048 | DTCM (32KB) | `GF22_TUD_2048x128` |

Port interface:
```
Output: Q[127:0]
Input:  ADR[N:0]  (9-bit for 512-depth, 11-bit for 2048-depth)
        D[127:0]
        WEM[127:0]  (bit write enable, active high)
        WE, ME, CLK
        TEST1, TEST_RNM, RME, RM[3:0]
        WA[1:0], WPULSE[2:0]
        LS, BC0, BC1, BC2
```

Replace `GF22_TUD_512x128` and `GF22_TUD_2048x128` in `hdl/verilog/Sram.v` with the actual module names from your memory compiler, then rebuild.

### Clock Gate Cell

Defined in `hdl/verilog/ClockGate.sv` under the `` `elsif GF22_TUD`` block (line 38).

Cell: `UDBLVT20_CKGTPLT_V5_8` (UDB LVT library)

Port mapping:
```
CK  <- clk_i
EN  <- enable
SE  <- te (test enable)
Q   -> clk_o
```

No L1 cache SRAMs are present in the `core_mini` variant (8KB/32KB TCM configuration).

## Synthesis Defines

### Required Defines

| Define | Purpose |
|---|---|
| `GF22_TUD` | Selects GF22 TUD SRAM macros and `UDBLVT20_CKGTPLT_V5_8` clock gate |
| `VLEN_128` | Sets `VLEN=128` throughout RVV RTL — elaboration fails without it |
| `ZVE32F_ON` | Enables FP execution units (FMA, FDIV, FSUB) in RVV backend |

### Tool Commands

```tcl
# Genus
set_db hdl_define_list {GF22_TUD VLEN_128 ZVE32F_ON}
read_hdl -sv RvvCoreMiniAxi_synth.sv

# DC
analyze -define {GF22_TUD VLEN_128 ZVE32F_ON} -format sverilog RvvCoreMiniAxi_synth.sv
```

### Complete Macro Reference

| Macro | Set for synthesis? | Effect |
|---|---|---|
| `GF22_TUD` | **Yes** | Selects GF22 TUD SRAM macros + `UDBLVT20` clock gate |
| `VLEN_128` | **Yes** | Defines `VLEN=128`; RVV RTL fails to elaborate without it |
| `ZVE32F_ON` | **Yes** | Instantiates FP units (FMA x2, FDIV x1, FSUB x4) in RVV backend |
| `TB_SUPPORT` | **No** | Adds 32-bit PC to FP retire tag for TB observability — unnecessary silicon area |
| `SYNTHESIS` | **No** | Only active in generic SRAM else-branch; irrelevant when `GF22_TUD` is set |
| `USE_GF22_116A` | **No** | Superseded by `GF22_TUD` |
| `USE_GF22` | **No** | Superseded by `GF22_TUD` |
| `DISPATCH3` | **No** | Increases dispatch to 3-wide + wider VRF ports; default (DISPATCH2) matches verified config |
| `ARBITER_ON` | **No** | Changes shared memory port count; not set in any sim config |
| `ZVFBFWMA_ON` | **No** | BF16 FMA; not set anywhere in the build |
| `ASSERT_ON` | **No** | Simulation assertions only |

## Related Files

| Path | Description |
|---|---|
| `hdl/chisel/src/coralnpu/BUILD` | Synthesis genrule targets (lines 783-812) |
| `hdl/verilog/Sram.v` | SRAM macro instantiations (`` `elsif GF22_TUD`` at line 114) |
| `hdl/verilog/ClockGate.sv` | Clock gate cell instantiation (`` `elsif GF22_TUD`` at line 38) |
| `rules/chisel.bzl` | `chisel_cc_library` rule that drives firtool emission |

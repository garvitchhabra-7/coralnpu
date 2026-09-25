# Generating VCU118 DDR4 IP

The VCU118 bitstream build requires DDR4 MIG IP from Xilinx/AMD. This IP is
proprietary and cannot be distributed in this repository. You must generate it
locally using Vivado.

Two flows are supported: **DCP** (pre-synthesized checkpoints, faster builds) and
**XCI** (IP source, regenerated each build).

---

## Prerequisites

- Vivado 2025.2 (or compatible version with VCU118 board files)
- VCU118 board files installed (check `$VIVADO_DIR/data/xhub/boards/XilinxBoardStore/boards/Xilinx/vcu118/`)
- Valid Vivado license for UltraScale+ synthesis

---

## Flow 1: DCP (Current Build Flow)

The build expects two DCP files and will fail without them:

```
fpga/ip/ddr4_vcu118/dcp/ddr_system_bd_ddr4_0_0.dcp     (~5.8 MB)
fpga/ip/ddr4_vcu118/dcp/ddr_system_bd_smartconnect_0_0.dcp  (~1.7 MB)
```

### Step 1: Create a Vivado project

```tcl
create_project ddr4_gen ./ddr4_gen -part xcvu9p-flga2104-2L-e
set_property BOARD_PART xilinx.com:vcu118:part0:2.4 [current_project]
```

### Step 2: Create a block design with DDR4 MIG

```tcl
create_bd_design "ddr_system_bd"

# Add DDR4 MIG IP using board preset (DDR4 SDRAM C1)
create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4 ddr4_0
apply_board_connection -board_interface "ddr4_sdram_c1" -ip_intf "ddr4_0/C0_DDR4" -diagram "ddr_system_bd"
apply_board_connection -board_interface "default_250mhz_clk1" -ip_intf "ddr4_0/C0_SYS_CLK" -diagram "ddr_system_bd"
```

### Step 3: Add SmartConnect for AXI width conversion

The MIG produces a 512-bit AXI master. CoralNPU needs 256-bit. Add a
SmartConnect to convert:

```tcl
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect smartconnect_0
set_property CONFIG.NUM_SI 1 [get_bd_cells smartconnect_0]
set_property CONFIG.NUM_MI 1 [get_bd_cells smartconnect_0]

# Connect SmartConnect master → MIG slave
connect_bd_intf_net [get_bd_intf_pins smartconnect_0/M00_AXI] \
                    [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]

# Clock and reset
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk] \
               [get_bd_pins smartconnect_0/aclk]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] \
               [get_bd_pins smartconnect_0/aresetn]
```

### Step 4: Make ports external

```tcl
# DDR4 pins
make_bd_intf_pins_external [get_bd_intf_pins ddr4_0/C0_DDR4]
make_bd_intf_pins_external [get_bd_intf_pins ddr4_0/C0_SYS_CLK]

# AXI slave (256-bit, from CoralNPU)
make_bd_intf_pins_external [get_bd_intf_pins smartconnect_0/S00_AXI]

# Clocks and resets
make_bd_pins_external [get_bd_pins ddr4_0/c0_ddr4_ui_clk]
make_bd_pins_external [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst]
make_bd_pins_external [get_bd_pins ddr4_0/c0_ddr4_aresetn]

# Debug (optional, left unconnected)
make_bd_pins_external [get_bd_pins ddr4_0/dbg_bus]
make_bd_pins_external [get_bd_pins ddr4_0/dbg_clk]

# c0_init_calib_complete
make_bd_pins_external [get_bd_pins ddr4_0/c0_init_calib_complete]
```

### Step 5: Validate and generate

```tcl
validate_bd_design
save_bd_design

# Generate HDL wrapper
make_wrapper -files [get_files ddr_system_bd.bd] -top
add_files -norecurse ./ddr4_gen/ddr4_gen.gen/sources_1/bd/ddr_system_bd/hdl/ddr_system_bd_wrapper.v

# Generate output products (Out of Context per IP)
generate_target all [get_files ddr_system_bd.bd]
```

### Step 6: Run OOC synthesis and extract DCPs

```tcl
# Synthesize the sub-IPs out of context
launch_runs synth_1 -jobs 8
wait_on_run synth_1
```

After synthesis completes, locate the DCPs:

```bash
# From the Vivado project directory:
find . -name "*.dcp" -path "*synth_1*" | grep -E "(ddr4_0_0|smartconnect_0_0)"
```

Typical paths:
```
./<project>.runs/ddr_system_bd_ddr4_0_0_synth_1/ddr_system_bd_ddr4_0_0.dcp
./<project>.runs/ddr_system_bd_smartconnect_0_0_synth_1/ddr_system_bd_smartconnect_0_0.dcp
```

### Step 7: Copy files into the repo

```bash
# DCPs
cp <project>/...runs/ddr_system_bd_ddr4_0_0_synth_1/ddr_system_bd_ddr4_0_0.dcp \
   fpga/ip/ddr4_vcu118/dcp/

cp <project>/...runs/ddr_system_bd_smartconnect_0_0_synth_1/ddr_system_bd_smartconnect_0_0.dcp \
   fpga/ip/ddr4_vcu118/dcp/
```

The following files are already checked into the repo (generated once, not proprietary):

- `rtl/ddr_system_bd_wrapper.v` — block design wrapper
- `rtl/ddr_system_bd.v` — block design netlist (instantiates IPs as black boxes)
- `xdc/ddr_system_bd_ddr4_0_0.xdc` — MIG timing constraints
- `xdc/ddr4_vcu118_pins.xdc` — explicit PACKAGE_PIN assignments for DDR4 C1
- `vivado_ddr4_vcu118_setup.tcl` — loads DCPs at build time

If regenerating with a different Vivado version, also update the wrapper and
netlist Verilog files from the new block design output.

### Step 8: Build the bitstream

```bash
bazel build //fpga:build_chip_vcu118_bitstream_highmem
```

---

## Flow 2: XCI (Alternative — Regenerate IP at Build Time)

Instead of pre-synthesized DCPs, this flow checks in only the Vivado IP
configuration file (`.xci`). Vivado regenerates and synthesizes the IP during
each build. This adds ~20-30 minutes to every build but avoids distributing
any Xilinx IP artifacts.

**This flow is not yet implemented.** The changes below outline what would be
needed.

### What is an XCI file?

An `.xci` is an XML file that records how an IP was configured (memory type,
width, frequency, board preset selections). It contains no RTL or netlists —
just configuration metadata. Vivado reads it and regenerates the full IP from
the Vivado installation's IP catalog.

### Generating the XCI

After creating the block design (Steps 1-4 above), export the IP XCI files:

```bash
# From the Vivado project directory:
find . -name "*.xci" -path "*ddr_system_bd*"
```

Typical paths:
```
./<project>.srcs/sources_1/bd/ddr_system_bd/ip/ddr_system_bd_ddr4_0_0/ddr_system_bd_ddr4_0_0.xci
./<project>.srcs/sources_1/bd/ddr_system_bd/ip/ddr_system_bd_smartconnect_0_0/ddr_system_bd_smartconnect_0_0.xci
```

Copy these into the repo:
```bash
mkdir -p fpga/ip/ddr4_vcu118/xci
cp <project>/...ip/ddr_system_bd_ddr4_0_0/ddr_system_bd_ddr4_0_0.xci \
   fpga/ip/ddr4_vcu118/xci/
cp <project>/...ip/ddr_system_bd_smartconnect_0_0/ddr_system_bd_smartconnect_0_0.xci \
   fpga/ip/ddr4_vcu118/xci/
```

### Required build system changes

1. **`ddr4_vcu118.core`** — replace `dcp_files` fileset with `xci_files`:
   ```yaml
   xci_files:
     files:
       - xci/ddr_system_bd_ddr4_0_0.xci: { file_type: xci }
       - xci/ddr_system_bd_smartconnect_0_0.xci: { file_type: xci }
   ```

2. **`vivado_ddr4_vcu118_setup.tcl`** — replace `add_files` for DCPs with XCI
   loading and OOC synthesis triggers. Vivado handles this automatically when
   XCIs are added as project sources.

3. **`BUILD`** — update glob to include `*.xci` instead of `*.dcp`.

### Trade-offs

| | DCP Flow | XCI Flow |
|---|---|---|
| Build time | ~6 hours | ~6.5 hours (+30 min IP synth) |
| Repo contents | Requires local DCP generation | XCI checked in (safe, ~50 KB) |
| Vivado version | DCPs tied to generating version | XCI regenerates for any version |
| Reproducibility | Exact netlist locked | May vary across Vivado versions |
| MIG constraint warnings | ~30 hierarchy path warnings | None (constraints resolve correctly) |

---

## Verification

After generating DCPs or XCIs, verify the build:

```bash
# Synthesis only (fast, ~1.5 hours)
bazel build //fpga:build_chip_vcu118_synth_only_highmem

# Full bitstream (~6 hours)
bazel build //fpga:build_chip_vcu118_bitstream_highmem
```

The bitstream output is in the Bazel cache:
```bash
find ~/.cache/bazel/ -name "chip_vcu118.bit" -printf '%T@ %p\n' | sort -rn | head -1
```

## MIG Configuration Reference

These are the settings used when generating the DDR4 MIG for VCU118:

| Parameter | Value |
|---|---|
| Board interface | DDR4 SDRAM C1 |
| Memory part | MT40A256M16LY-062E (4 Gb ×16, auto-selected) |
| Reference clock | 250 MHz (`default_250mhz_clk1`, pins E12/D12) |
| Data width | 64-bit (non-ECC) |
| Bank groups | 1 (BG0 only) |
| MIG native AXI | 512-bit data, 31-bit addr |
| SmartConnect conversion | 256-bit/34-bit slave ↔ 512-bit/31-bit master |
| Ranks | 1 |

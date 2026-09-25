# CoralNPU FPGA Flow

## Overview

The `fpga/` directory contains a full SoC integration of the CoralNPU core for FPGA prototyping. The build system uses FuseSoC (`.core` files) orchestrated by Bazel (`fusesoc_build` rule), targeting Vivado for synthesis and Verilator for simulation.

The current target board is called "Nexus" — a custom Google lab board with a Xilinx VU13P (`xcvu13p-fhga2104-2-e`) and a Zynq SOM companion for bitstream loading.

## RTL Hierarchy

```
chip_nexus.sv                    -- Board-level top (Nexus-specific)
├── clkgen_wrapper.sv            -- Clock generation
│   └── clkgen_xilultrascaleplus.sv  -- MMCME2_ADV: 100MHz diff → 50MHz core, 100MHz SPI, 1MHz ISP
├── dmi_jtag                     -- RISC-V debug module (JTAG TAP, IdcodeValue 0x04f5484d)
├── ddr4 MIG IP                  -- Xilinx DDR4 memory controller (ddr_system_bd_ddr4_0_0)
├── STARTUPE3                    -- Xilinx startup primitive
├── IOBUF instances              -- GPIO (4 bidir), I2C tri-state
└── coralnpu_soc.sv              -- Board-agnostic SoC integration
    ├── CoralNPUChiselSubsystem  -- Chisel-generated core (scalar + RVV + FPU + bus fabric + TCMs)
    ├── uart ×2                  -- OpenTitan UART IP (via TileLink)
    ├── i2c_master               -- I2C master (via TileLink)
    ├── isp_wrapper              -- Camera ISP (DVP 8-bit interface, AXI master for DMA)
    ├── prim_rom_adv             -- Boot ROM (32KB, 8192×32-bit)
    ├── clk_table                -- Clock frequency readback CSR
    └── autoboot                 -- Optional HW state machine to release clock gate + reset
```

Key point: `coralnpu_soc.sv` is **board-agnostic**. It takes clocks, reset, SPI, UART sidebands, GPIO, I2C, camera DVP, DDR AXI, and debug module interfaces as ports. The board-specific `chip_*.sv` wrapper handles pin-level I/O, clock generation, DDR MIG, and JTAG.

## Memory Variants

Two Chisel subsystem configurations are pre-built:

| Variant | ITCM | DTCM | CSR Base | Chisel Target |
|---|---|---|---|---|
| `default` | 8 KB | 32 KB | `0x00030000` | `coralnpu_chisel_subsystem_default` |
| `highmem` | 1 MB | 1 MB | `0x00200000` | `coralnpu_chisel_subsystem_highmem` |

The CSR base address is auto-selected in `coralnpu_soc.sv:197`:
```
localparam logic [31:0] CsrBaseAddr = (ItcmSizeKBytes == 8 && DtcmSizeKBytes == 32) ? 32'h00030000 : 32'h00200000;
```

## Boot Modes

### 1. ITCM Boot (default)
- PC starts at `0x0` (ITCM base)
- Program loaded externally via SPI slave interface from host PC
- Used by `nexus_loader` tool and simulation tests

### 2. ROM Boot
- PC starts at `0x10000000` (ROM base, set via `BootAddr` parameter)
- Boot ROM (`fpga/sw/rom_boot/main.c`) executes:
  1. Init UART + SPI flash
  2. Read ROM header at flash offset 0 (magic: `0x544f4f42` = "BOOT")
  3. Parse ZIP central directory, find `BOOT.ELF`
  4. Parse ELF program headers
  5. DMA-load PT_LOAD segments from SPI flash → ITCM/DTCM
  6. Jump to ELF entry point
- Enabled with `EnableAutoboot=1` and `BootAddr=268435456` (0x10000000)
- The `autoboot.sv` module releases clock gate then reset via TileLink writes to the CSR base

### 3. No ARM SoC Needed
The CoralNPU is a self-contained RISC-V processor, not a coprocessor. It boots and runs programs independently. The Zynq SOM on the Nexus board is only for FPGA bitstream loading (`zturn`), not runtime control.

## Build Targets (Bazel)

### Verilator Simulation
```bash
# Default memory (8KB ITCM / 32KB DTCM)
bazel build //fpga:build_chip_verilator

# Highmem (1MB / 1MB) — needed for ML workloads
bazel build //fpga:build_chip_verilator_highmem

# ROM boot variants
bazel build //fpga:build_chip_verilator_rom
bazel build //fpga:build_chip_verilator_highmem_rom
```

Verilator options include `-DVLEN_128` (RVV vector length 128), `-DUSE_GENERIC`, `-DTB_SUPPORT`, and thread count auto-detected from `nproc`.

### Vivado Bitstream (tagged `manual`, needs Vivado license)
```bash
# Full PnR + bitstream
bazel build //fpga:build_chip_nexus_bitstream_highmem

# Synthesis only (faster, checks if design fits)
bazel build //fpga:build_chip_nexus_synth_only_highmem

# ROM boot variants
bazel build //fpga:build_chip_nexus_bitstream_highmem_rom
```

### Pre-built Bitstreams
```bash
fpga/get_bitstream.sh --latest --target nexus
```
Fetches from Google Artifact Registry (`cerebra-shodan-ci-public`), searching recent commits that touched `fpga/` or `hdl/chisel/src/soc/`.

## FuseSoC Core Files

- `coralnpu_soc.core` — SoC integration, depends on Chisel subsystem, UART, ROM, I2C, ISP
- `chip_nexus.core` — Nexus board top, depends on `coralnpu_soc`, RISC-V debug, DDR4 MIG
- `chip_verilator.core` — Verilator simulation top with DPI modules
- `coralnpu_soc_pkg.core` / `racl_pkg.core` — Package dependencies

Synthesis target in `chip_nexus.core` sets `FPGA_XILINX=true`, `USE_GENERIC=true`, `TB_SUPPORT=true`, `VLEN_128=true`, `ZVE32F_ON=true`.

## Peripherals and SW HALs

The `fpga/sw/` directory has bare-metal HAL libraries:

| Library | Files | Purpose |
|---|---|---|
| `uart` | `uart.c/h` | UART init, putc, getc |
| `spi` | `spi.c/h` | SPI master driver |
| `spi_flash` | `spi_flash.c/h` | SPI flash read/write/erase, DMA read |
| `i2c` | `i2c.c/h` | I2C master driver |
| `gpio` | `gpio.c/h` | GPIO read/write/direction |
| `dma` | `dma.c/h` | DMA engine driver |
| `clk` | `clk.c/h` | Clock frequency readback |
| `display_renderer` | `display_renderer.cc/h` | Waveshare SPI display with DMA |
| `display_hal` | `display_hal.c` | Display low-level HAL |

Test binaries built with `coralnpu_v2_binary` rule: `spi_test`, `gpio_test`, `dma_test`, `i2c_camera_test`, `display_test`, `flash_tool`, `timer`, `isp_cam_test`.

Simulation tests use `coralnpu_v2_sim_test` rule which builds the binary, runs it on the Verilator sim, and checks pass/fail via UART output.

## IP Blocks (`fpga/ip/`)

- `coralnpu_chisel_subsystem_default` / `_highmem` — Pre-generated Chisel RTL for each memory config
- `coralnpu_tlul` — TileLink-UL package definitions
- `i2c_master` — I2C master IP with TileLink interface
- `ispyocto` — Camera ISP wrapper (external IP, patched via `ispyocto_core.patch`)
- `ddr4_stub` — DDR4 stub for builds without the internal MIG IP (ties off all AXI signals)
- `display_dpi` / `gpio_dpi` / `spi_dpi_master` / `s25fl512s_dpi` — DPI models for Verilator sim
- `hm01b0_model` — Camera sensor model for simulation

## DDR4 Path

The DDR4 interface uses two AXI ports from `coralnpu_soc.sv`:
1. `io_ddr_ctrl_axi` — 32-bit data, for MIG control registers
2. `io_ddr_mem_axi` — 256-bit data (1-bit ID), for bulk memory access at `0x80000000`

In `chip_nexus.sv`, these connect to the Xilinx DDR4 MIG IP which presents a 256-bit AXI slave on the `c0_ddr4_ui_clk` domain. The SoC's `CoralNPUChiselSubsystem` has async clock domain crossings for the DDR clock.

The internal MIG IP is in `internal/fpga/ip/ddr4/` (not open-source). The open-source repo uses `fpga/ip/ddr4_stub/` which stubs all AXI responses (never ready).

## Vivado Hooks

Several TCL scripts are used during the Vivado flow:
- `vivado_setup_hooks.tcl` — Registers other hooks
- `vivado_pre_opt_hooks.tcl` — Pre-optimization constraints
- `vivado_hook_write_bitstream_post.tcl` — Post-bitstream generation
- `pblock_u_isp.tcl` / `pblock_u_ddr.tcl` — Placement constraints for ISP and DDR
- `check_pin_assignments.tcl` — Validates pin assignments
- `create_final_mmi.tcl` / `extract_bram_details.tcl` — BRAM initialization file generation
- `convert_stitched_to_bin_smap.tcl` — Bitstream format conversion

## Key Files for Porting to a New Board

To target a new FPGA board, you need:
1. `chip_<board>.sv` — New board-level top (adapt from `chip_nexus.sv`)
2. `pins_<board>.xdc` — Pin constraint file for your board
3. `chip_<board>.core` — FuseSoC core with your FPGA part number
4. DDR controller IP — Regenerate MIG or equivalent for your board's DDR
5. Clock gen — May need adaptation if input clock differs from 100 MHz
6. `fpga/BUILD` updates — Add new `fusesoc_build` targets

`coralnpu_soc.sv` and all Chisel-generated RTL remain unchanged.

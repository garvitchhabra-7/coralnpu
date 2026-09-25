# VCU118 Porting Plan

## Goal

Port the CoralNPU FPGA design from Nexus (XCVU13P) to VCU118 (XCVU9P). Target: highmem variant (1MB ITCM + 1MB DTCM), running MobileNet with sample images loaded through DDR4/TCM. No camera/ISP needed.

## Scope

**In scope:**
- Board-level RTL wrapper (`chip_vcu118.sv`)
- Pin constraints (`pins_vcu118.xdc`)
- DDR4 MIG IP generation for VCU118
- FuseSoC core file (`chip_vcu118.core`)
- Bazel BUILD targets for VCU118
- Vivado hooks adaptation (pblocks, pin checks)
- Bring-up validation (UART, JTAG, DDR4, basic program execution)

**Out of scope:**
- Camera/ISP interface (no camera in this demo)
- Display interface (nice-to-have later, not blocking)
- ROM boot from SPI flash (ITCM boot via SPI slave is sufficient)
- Any changes to `coralnpu_soc.sv` or Chisel-generated RTL

## Phases

---

### Phase 1: RTL — Board Wrapper

**Task 1.1: Write `fpga/rtl/chip_vcu118.sv`**

Adapt from `fpga/rtl/chip_nexus.sv` (510 lines). The structure is:

```
chip_vcu118
├── STARTUPE3              -- Keep as-is (same primitive on XCVU9P)
├── clkgen_wrapper          -- Reuse clkgen_xilultrascaleplus.sv unchanged
│                              VCU118 SI5335A provides 100MHz diff, same as Nexus
├── dmi_jtag               -- Keep as-is, just remap JTAG pins in XDC
├── DDR4 MIG instantiation  -- Replace ddr_system_bd_ddr4_0_0 with VCU118 MIG
│                              Module name will come from Vivado IP gen
├── IOBUF instances         -- GPIO: 4 bidir via IOBUF (map to VCU118 GPIO pins)
│                              I2C: keep SCL/SDA IOBUFs (map to PMOD pins)
├── UART sideband wiring    -- Map to VCU118 USB-UART CP2105 pins
└── coralnpu_soc            -- Instantiate unchanged
```

Key changes from `chip_nexus.sv`:

1. **Remove camera ports entirely** — no `ISP_DVP_*`, `CAM_INT`, `CAM_TRIG` at the top-level. The `coralnpu_soc` still has these ports; tie them off:
   ```systemverilog
   .ISP_DVP_D0(1'b0), .ISP_DVP_D1(1'b0), ... .ISP_DVP_D7(1'b0),
   .ISP_DVP_PCLK(1'b0), .ISP_DVP_HSYNC(1'b0), .ISP_DVP_VSYNC(1'b0),
   .CAM_INT(1'b0), .CAM_TRIG()  // leave output unconnected
   ```

2. **DDR4 MIG module name** — will differ from `ddr_system_bd_ddr4_0_0`. The VCU118 MIG IP (generated in Phase 2) will have its own module name and possibly different port names. The AXI interface widths should remain the same (256-bit data, 34-bit addr).

3. **DDR4 reset logic** — keep the same pattern:
   ```systemverilog
   assign mig_sys_rst = (~locked) | (~eos) | (~rst_ni);
   ```

4. **Debug LEDs** — map `io_halted`, `io_fault`, `ddr_cal_complete_o` to VCU118's 8 user LEDs (GPIO_LED_0..7). The Nexus maps 7 signals to LEDs; VCU118 has 8 LEDs available.

5. **SPI slave** — route to PMOD J52 pins (for host program loading via `nexus_loader`/FTDI).

6. **SPI master** — route to PMOD J53 pins (or tie off if not using flash/display initially).

7. **SPI flash master** — the on-board QSPI flash is accessed via STARTUPE3 for bitstream. If we want runtime SPI flash access, route `spim_flash_*` to PMOD or leave tied off for now.

8. **I2C** — not needed without camera. Tie off or route to PMOD if desired.

9. **GPIO** — map to on-board buttons/LEDs or PMOD pins.

**Task 1.2: ISP clock tie-off**

`coralnpu_soc` requires `clk_isp_i`. The ISP is still instantiated inside `coralnpu_soc.sv` even though we won't use the camera. The ISP needs a clock to avoid metastability issues with the async CDC. Keep generating `clk_isp` from the MMCME2_ADV (it's free — already produced by CLKOUT4).

---

### Phase 2: DDR4 MIG IP Generation

**Task 2.1: Generate VCU118 DDR4 MIG IP in Vivado**

This is the most involved step. Must be done interactively in Vivado GUI.

1. Open Vivado, create a project targeting `xcvu9p-flga2104-2-e`
2. IP Catalog → Memory Interface Generator (MIG) → DDR4 SDRAM
3. Configure for VCU118 DDR4 Channel 1:
   - Memory Part: MT40A256M16GE-083E (matches VCU118 BOM)
   - Data Width: 64-bit (+ 8-bit ECC = 72-bit physical, 80-bit with DBI)
   - AXI Data Width: 256-bit (must match CoralNPU's `io_ddr_mem_axi` interface)
   - AXI ID Width: 1 (must match — CoralNPU uses 1-bit ID on mem AXI)
   - AXI Address Width: 34 (matches Nexus)
   - Reference Clock: 300 MHz (VCU118 dedicated DDR4 ref clock)
   - System Clock: differential
4. Pin assignment: use Vivado's VCU118 board file or UG1224 DDR4 pinout table
5. Generate IP, note the module name (likely `ddr4_0` or similar)

**Task 2.2: Create `fpga/ip/ddr4_vcu118/` directory**

Structure:
```
fpga/ip/ddr4_vcu118/
├── BUILD
├── ddr4_vcu118.core      -- FuseSoC core referencing the generated RTL
├── rtl/                  -- Generated MIG IP output files
└── pins_ddr_vcu118.xdc   -- DDR4-specific pin constraints (from MIG generation)
```

The MIG generates its own XDC for DDR4 pins — extract and place here.

**Task 2.3: AXI interface matching**

Verify the generated MIG's AXI slave interface matches what `coralnpu_soc.sv` expects:
- `io_ddr_mem_axi`: 256-bit data, 1-bit ID, 34-bit address, 8-bit len, standard AXI4
- `io_ddr_ctrl_axi`: 32-bit data, for MIG control registers (ECC, calibration status)

If the MIG IP uses different signal names than `ddr_system_bd_ddr4_0_0`, update the instantiation in `chip_vcu118.sv` accordingly.

---

### Phase 3: Pin Constraints

**Task 3.1: Write `fpga/pins_vcu118.xdc`**

Reference: Xilinx UG1224 (VCU118 Evaluation Board User Guide), XTP433 schematic.

Required pin mappings:

```
# Clocks
- System clock:       SI5335A 100MHz diff pair → clk_p_i, clk_n_i
                       VCU118: SYSCLK_300_P/N (or USER_SI570 at 156.25MHz)
                       Need to identify the 100MHz output pins
- DDR4 ref clock:     300MHz dedicated diff pair → c0_sys_clk_p/n
                       VCU118: DDR4_C1_SYS_CLK_P/N

# UART (USB-UART bridge CP2105)
- uart_tx_o[0]:       USB-UART channel 1 TX
- uart_rx_i[0]:       USB-UART channel 1 RX
- uart_tx_o[1]:       USB-UART channel 2 TX
- uart_rx_i[1]:       USB-UART channel 2 RX

# JTAG (14-pin header J53 or board header)
- tck_i, tms_i, td_i, td_o, trst_ni
  Note: VCU118 JTAG header is shared with Vivado. For CoralNPU JTAG,
  use PMOD pins or FMC pins to avoid conflict with Vivado JTAG.
  Alternative: route through PMOD J52 or J53.

# Reset
- rst_ni:             Push button (active low)
                       VCU118: CPU_RESET (SW1)

# SPI Slave (host program loading) → PMOD J52
- spi_clk_i, spi_csb_i, spi_mosi_i, spi_miso_o
  Map to 4 PMOD J52 pins

# Status LEDs
- io_halted:          GPIO_LED_0
- io_fault:           GPIO_LED_1
- ddr_cal_complete_o: GPIO_LED_2
- ddr_ui_clk:         GPIO_LED_3 (optional, for debug)

# GPIO (directly to LEDs/buttons, no IOBUF needed)
- gpio[0..3]:         GPIO_LED_4..7 or DIP switches

# DDR4 pins → from MIG IP generation (separate XDC)
```

**Task 3.2: Clock constraints**

```tcl
# System clock (need to verify which VCU118 clock is 100MHz)
create_clock -period 10.00 -name sys_clk_pin [get_ports clk_p_i]
# DDR4 reference clock
create_clock -period 3.333 -name c0_sys_clk_p [get_ports c0_sys_clk_p]
# SPI clock (12 MHz from FTDI)
create_clock -period 83.333 -name spi_clk_i [get_ports spi_clk_i]
# JTAG clock
create_clock -period 2000.00 -name jtag_tck_i [get_ports tck_i]

# Async clock groups (same pattern as Nexus)
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks sys_clk_pin] \
  -group [get_clocks -include_generated_clocks c0_sys_clk_p] \
  -group [get_clocks spi_clk_i] \
  -group [get_clocks jtag_tck_i]
```

Note: No `ISP_DVP_PCLK` clock — we're not using the camera.

**Task 3.3: Identify VCU118 100MHz clock source**

Critical decision: The VCU118 has multiple clock sources:
- SI5335A: outputs at 100/125/300 MHz on various pins
- Si570: 156.25 MHz (user-programmable)
- SYSCLK_300: 300 MHz diff pair

The Nexus design expects 100 MHz. Need to check UG1224 for which SI5335A output is 100 MHz and its pin location. If no 100 MHz is available, we can either:
- Use the Si570 (program it to 100 MHz via I2C at startup) 
- Use 125 MHz and adjust the MMCME2_ADV divider (change `CLKIN1_PERIOD` from 10.0 to 8.0 ns and adjust `CLKFBOUT_MULT_F`)

---

### Phase 4: FuseSoC and Build Integration

**Task 4.1: Write `fpga/chip_vcu118.core`**

```yaml
CAPI=2:
name: "com.google.coralnpu:fpga:chip_vcu118:0.1"
description: "VCU118-specific top-level for CoralNPU."

filesets:
  files_rtl:
    depend:
      - com.google.coralnpu:fpga:coralnpu_soc
      - pulp-platform:riscv-dbg:0.1
      - com.google.coralnpu:fpga:ddr4_vcu118   # New DDR4 IP
    files:
      - rtl/chip_vcu118.sv
      - rtl/clkgen_wrapper.sv
      - rtl/clkgen_xilultrascaleplus.sv
    file_type: systemVerilogSource

  files_constraints:
    files:
      - pins_vcu118.xdc
    file_type: xdc

  files_tcl:
    files:
      - vivado_setup_hooks.tcl: { file_type: tclSource }
      - vivado_hook_write_bitstream_post.tcl: { file_type: user, copyto: ... }
      # May need adapted pblock scripts or skip them

targets:
  synth:
    toplevel: chip_vcu118
    default_tool: vivado
    parameters: [same as chip_nexus.core]
    tools:
      vivado:
        part: "xcvu9p-flga2104-2-e"
```

**Task 4.2: Update `fpga/BUILD`**

Add VCU118 targets following the existing template pattern. Need:
- `DDR_CORES_VCU118` and `DDR_SRCS_VCU118` lists pointing to the new DDR4 IP
- `_VCU118_NAME_MAP` for bitstream and synth_only targets
- `template_rule(fusesoc_build, ...)` for VCU118

Since we only need highmem and no ROM boot for now, can start with a single target:
```python
fusesoc_build(
    name = "build_chip_vcu118_bitstream_highmem",
    ...
)
```

**Task 4.3: Adapt Vivado hooks**

- `vivado_setup_hooks.tcl` — likely reusable as-is (registers other hooks, fixes MemInitFile paths)
- `vivado_pre_opt_hooks.tcl` — sources pblock scripts. Remove `pblock_u_isp.tcl` (no camera) and `pblock_u_ddr.tcl` (DDR4 placement will differ). May need new VCU118-specific pblocks if SLR crossing is an issue.
- `vivado_hook_write_bitstream_post.tcl` — DDR4 calibration FW stitching. Needs adaptation for the new MIG IP directory name.
- `check_pin_assignments.tcl` — needs the new XDC file

---

### Phase 5: Initial Synthesis (No DDR4)

**Task 5.1: First synthesis without DDR4**

To validate the basic design fits before dealing with DDR4 MIG complexity:
1. Use the `ddr4_stub` instead of real MIG IP
2. Target `xcvu9p-flga2104-2-e`
3. Run synth_only to check: resource utilization, timing, any primitive issues

This catches any part-specific issues early without the DDR4 variable.

**Task 5.2: Verify resource utilization**

Expected: ~7% LUT, ~26% BRAM, ~2% DSP. If significantly different, investigate.

---

### Phase 6: DDR4 Integration and Full Bitstream

**Task 6.1: Integrate real DDR4 MIG**

Replace `ddr4_stub` with the generated VCU118 MIG IP. Wire up in `chip_vcu118.sv`. Add DDR4 pin constraints.

**Task 6.2: Full synthesis + PnR + bitstream**

Run the full Vivado flow. Watch for:
- DDR4 timing closure (MIG has strict timing)
- SLR crossing violations (add pblocks if needed)
- Hold violations on async paths (soft reset / CDC)

**Task 6.3: Generate bitstream**

Output: `chip_vcu118.bin` or `chip_vcu118.bit` for FPGA programming.

---

### Phase 7: Board Bring-Up

**Task 7.1: Program FPGA**

Program VCU118 via Vivado Hardware Manager + JTAG cable. Verify:
- LEDs respond (halted/fault/DDR cal)
- DDR4 calibration completes (LED goes high, ~1 second)

**Task 7.2: UART verification**

Connect USB cable to VCU118 USB-UART port. Open serial terminal (115200 baud). No output expected yet — just verify the port enumerates.

**Task 7.3: SPI program loading**

Connect FTDI adapter to PMOD J52 SPI pins. Use `nexus_loader` (or adapt it) to:
1. Write a word to ITCM via SPI → read it back → verify
2. Load `trivial_pass_test` binary → verify UART output "PASS"

**Task 7.4: DDR4 verification**

Write a simple test program that:
1. Waits for DDR calibration (poll status or just wait 2 seconds)
2. Writes pattern to `0x80000000`
3. Reads it back
4. Prints PASS/FAIL on UART

**Task 7.5: JTAG debug verification**

Connect OpenOCD to the RISC-V debug module. Verify:
- Can halt/resume the core
- Can read/write registers
- Can set breakpoints

---

### Phase 8: MobileNet Demo

**Task 8.1: Build MobileNet binary**

Use TFLite Micro (`sw/opt/litert-micro/`) to:
1. Convert MobileNet v1/v2 (or a smaller variant like MobileNet v2 0.25x 96) to TFLite format
2. Quantize to int8 (fits better in limited TCM)
3. Build with `coralnpu_v2_binary` for highmem

**Task 8.2: Embed sample images**

Embed 2-3 test images as C arrays (e.g., `const uint8_t image_data[] = {...}`) in the binary, or load them into DDR4 from the host before running.

**Task 8.3: Run inference**

Load binary → run on NPU → print classification results on UART.

---

## File Inventory (New Files to Create)

| File | Based On | Status |
|---|---|---|
| `fpga/rtl/chip_vcu118.sv` | `fpga/rtl/chip_nexus.sv` | To create |
| `fpga/pins_vcu118.xdc` | `fpga/pins_nexus.xdc` + UG1224 | To create |
| `fpga/chip_vcu118.core` | `fpga/chip_nexus.core` | To create |
| `fpga/ip/ddr4_vcu118/` | Vivado MIG IP gen | To create |
| `fpga/BUILD` | Existing (add targets) | To modify |
| `fpga/vivado_pre_opt_hooks_vcu118.tcl` | `fpga/vivado_pre_opt_hooks.tcl` | Maybe (remove ISP pblock) |

## Files NOT Modified

- `fpga/rtl/coralnpu_soc.sv` — board-agnostic, untouched
- `fpga/rtl/clkgen_wrapper.sv` — reused directly
- `fpga/rtl/clkgen_xilultrascaleplus.sv` — reused directly (if 100MHz input available)
- All Chisel-generated RTL
- All SW HALs and libraries
- `fpga/rtl/autoboot.sv`, `fpga/rtl/clk_table.sv`, `fpga/rtl/top_pkg.sv`

## Open Questions

1. **VCU118 100 MHz clock source** — which SI5335A output provides 100 MHz and on which pins? If none, need to adjust the MMCME2_ADV or use Si570.

2. **JTAG pin routing** — the VCU118's JTAG header is used by Vivado. The CoralNPU RISC-V debug JTAG needs separate pins (PMOD or FMC). Need to decide where.

3. **SPI slave host tool** — `nexus_loader` talks to the Nexus FTDI over SPI. Need to verify it works with a generic FTDI adapter connected to PMOD pins, or adapt it.

4. **DDR4 address width** — Nexus uses 34-bit AXI address. VCU118's DDR4 may need different address mapping depending on the MIG configuration. Verify the base address `0x80000000` still works.

5. **Board revision** — need to check if the VCU118 on hand is rev 2.0+ (QSPI flash) or earlier (BPI). Affects bitstream storage but not the initial bring-up.

## Execution Order

Start with Phase 1 + 3 + 4 in parallel (RTL wrapper, XDC, build integration), since they're independent. Phase 2 (DDR4 MIG) requires Vivado GUI work. Phase 5 (synth without DDR4) can run as soon as 1+3+4 are done. Phases 6-8 are sequential.

**Estimated total: 2-4 days** to first bitstream, assuming the 100 MHz clock question is resolved quickly and DDR4 MIG generation goes smoothly.

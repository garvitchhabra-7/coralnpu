# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# =============================================================================
# VCU118 Pin Constraints for CoralNPU
# Reference: Xilinx UG1224 (VCU118 Evaluation Board User Guide)
# Pin locations verified against part0_pins.xml and master.xdc (XTP450).
# PMOD0 = J53 (Bank 67, LVCMOS18), PMOD1 = J52 (Bank 47, LVCMOS12).
# =============================================================================

# -----------------------------------------------------------------------------
# System Clock — 125 MHz LVDS from SI5335A
# Requires clkgen_xilultrascaleplus_vcu118.sv parameter update:
#   CLKIN1_PERIOD = 8.0 ns, DIVCLK_DIVIDE = 5, CLKFBOUT_MULT_F = 48.0 (VCO = 1200 MHz)
# Verified: part0_pins.xml sysclk_125_p=AY24, sysclk_125_n=AY23
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN AY24 IOSTANDARD LVDS } [get_ports { clk_p_i }];
set_property -dict { PACKAGE_PIN AY23 IOSTANDARD LVDS } [get_ports { clk_n_i }];
create_clock -period 8.000 -name sys_clk_pin -waveform {0 4} [get_ports clk_p_i]

# DDR4 Reference Clock — 250 MHz dedicated pair for MIG (C1)
# Verified: master.xdc 250MHZ_CLK1_P=E12, 250MHZ_CLK1_N=D12, Bank 71, DIFF_SSTL12
set_property -dict { PACKAGE_PIN E12 IOSTANDARD DIFF_SSTL12 } [get_ports { c0_sys_clk_p }];
set_property -dict { PACKAGE_PIN D12 IOSTANDARD DIFF_SSTL12 } [get_ports { c0_sys_clk_n }];
create_clock -period 4.000 -name c0_sys_clk_p [get_ports c0_sys_clk_p]

# Generated Clocks
create_generated_clock -name clk_main [get_pin i_clkgen/i_clkgen/pll/CLKOUT0]
create_generated_clock -name clk_aon [get_pin i_clkgen/i_clkgen/pll/CLKOUT4]

# -----------------------------------------------------------------------------
# Reset — VCU118 CPU_RESET button
# board.xml shows rst_polarity=1 (active HIGH on board). The port keeps the
# name rst_ni, but chip_vcu118.sv inverts it at the pad (rst_n_pad = ~rst_ni).
# PULLDOWN keeps the idle (unpressed = run) level defined.
# Verified: part0_pins.xml CPU_RESET=L19 LVCMOS12
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN L19 IOSTANDARD LVCMOS12 PULLTYPE PULLDOWN } [get_ports { rst_ni }];

# -----------------------------------------------------------------------------
# JTAG — PMOD0 (J53) pins 0-4, Bank 67, LVCMOS18
# Verified: master.xdc (XTP450) PMOD0_0-4_LS
# -----------------------------------------------------------------------------
create_clock -period 2000.00 -name jtag_tck_i -waveform {0 1000} [get_ports {tck_i}]
set_property -dict { PACKAGE_PIN AY14 IOSTANDARD LVCMOS18 PULLTYPE PULLDOWN } [get_ports {tck_i}]
set_property -dict { PACKAGE_PIN AY15 IOSTANDARD LVCMOS18 PULLTYPE PULLDOWN } [get_ports {tms_i}]
set_property -dict { PACKAGE_PIN AW15 IOSTANDARD LVCMOS18 PULLTYPE PULLDOWN } [get_ports {td_i}]
set_property -dict { PACKAGE_PIN AV15 IOSTANDARD LVCMOS18 PULLTYPE PULLDOWN } [get_ports {td_o}]
set_property -dict { PACKAGE_PIN AV16 IOSTANDARD LVCMOS18 } [get_ports {trst_ni}]

# -----------------------------------------------------------------------------
# SPI Slave (host program loading via FTDI) — PMOD1 (J52) pins 0-3, Bank 47
# Verified: master.xdc (XTP450) PMOD1_0-3_LS
# -----------------------------------------------------------------------------
create_clock -period 83.333 -name spi_clk_i -waveform {0 41.667} [get_ports spi_clk_i]
set_property -dict { PACKAGE_PIN N28 IOSTANDARD LVCMOS12 } [get_ports { spi_clk_i }];
set_property -dict { PACKAGE_PIN M30 IOSTANDARD LVCMOS12 } [get_ports { spi_csb_i }];
set_property -dict { PACKAGE_PIN N30 IOSTANDARD LVCMOS12 } [get_ports { spi_mosi_i }];
set_property -dict { PACKAGE_PIN P30 IOSTANDARD LVCMOS12 } [get_ports { spi_miso_o }];

# SPI Master — PMOD1 (J52) pins 4-7, Bank 47
# Verified: master.xdc (XTP450) PMOD1_4-7_LS
set_property -dict { PACKAGE_PIN P29 IOSTANDARD LVCMOS12 } [get_ports { spim_sclk_o }];
set_property -dict { PACKAGE_PIN L31 IOSTANDARD LVCMOS12 } [get_ports { spim_csb_o }];
set_property -dict { PACKAGE_PIN M31 IOSTANDARD LVCMOS12 } [get_ports { spim_mosi_o }];
set_property -dict { PACKAGE_PIN R29 IOSTANDARD LVCMOS12 } [get_ports { spim_miso_i }];

# SPI Flash — not exposed on VCU118. PMOD0 has only 3 pins left after JTAG, so
# CS/RESET previously landed on push buttons BD23 (GPIO_SW_C) / BF22 (GPIO_SW_W),
# driving outputs into active-high switches. No flash is wired, so the ports were
# removed from chip_vcu118.sv and the SPI flash master is tied off internally.

# -----------------------------------------------------------------------------
# Non-GCIO clock routing overrides
# PMOD pins are not clock-capable (GCIO), but JTAG TCK and SPI slave clock
# are low-speed and safe to route through fabric instead of dedicated routes.
# Same pattern as Nexus ISP_DVP_PCLK.
# -----------------------------------------------------------------------------
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -of_objects [get_ports tck_i]]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -of_objects [get_ports spi_clk_i]]

# -----------------------------------------------------------------------------
# UART — VCU118 USB-to-UART bridge (Silicon Labs CP2105)
# Only one channel exposed in board files. Second channel goes to
# system controller and is not directly accessible.
# Verified: part0_pins.xml USB_UART_TX=BB21, USB_UART_RX=AW25
# Naming is from FPGA perspective: TX=FPGA output to host, RX=FPGA input
# -----------------------------------------------------------------------------
# UART1 is the console: fpga/sw/uart.c writes to UART1_BASE (0x40010000), and
# Nexus also puts uart[1] on its USB UART. So uart[1] gets the real TX/RX.
set_property -dict { PACKAGE_PIN BB21 IOSTANDARD LVCMOS18 } [get_ports { uart_tx_o[1] }];
set_property -dict { PACKAGE_PIN AW25 IOSTANDARD LVCMOS18 } [get_ports { uart_rx_i[1] }];
# UART0 — no second channel on VCU118 USB-UART bridge.
# Routed to CTS/RTS pins (unused) as harmless stubs to satisfy port binding.
# Verified: part0_pins.xml USB_UART_CTS=BB22, USB_UART_RTS=AY25
set_property -dict { PACKAGE_PIN BB22 IOSTANDARD LVCMOS18 } [get_ports { uart_tx_o[0] }];
set_property -dict { PACKAGE_PIN AY25 IOSTANDARD LVCMOS18 } [get_ports { uart_rx_i[0] }];

# -----------------------------------------------------------------------------
# LEDs — VCU118 has 8 user LEDs (active high, directly driven)
# Verified: part0_pins.xml GPIO_LED_0-6 = AT32,AV34,AY30,BB32,BF32,AU37,AV36
# -----------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN AT32 DRIVE 8 IOSTANDARD LVCMOS12 } [get_ports { io_halted }];
set_property -dict { PACKAGE_PIN AV34 DRIVE 8 IOSTANDARD LVCMOS12 } [get_ports { io_fault }];
set_property -dict { PACKAGE_PIN AY30 DRIVE 8 IOSTANDARD LVCMOS12 } [get_ports { ddr_cal_complete_o }];
set_property -dict { PACKAGE_PIN BB32 DRIVE 8 IOSTANDARD LVCMOS12 } [get_ports { io_ddr_mem_axi_aw_ready }];
set_property -dict { PACKAGE_PIN BF32 DRIVE 8 IOSTANDARD LVCMOS12 } [get_ports { io_ddr_mem_axi_ar_ready }];
set_property -dict { PACKAGE_PIN AU37 DRIVE 8 IOSTANDARD LVCMOS12 } [get_ports { ddr_ui_clk }];
set_property -dict { PACKAGE_PIN AV36 DRIVE 8 IOSTANDARD LVCMOS12 } [get_ports { ddr_ui_clk_sync_rst }];

# GPIO — removed: VCU118 DIP switches (B17, G16, J16, D21) are in HP banks 72/73
# which don't support LVCMOS12. GPIO tied off internally.

# I2C — VCU118 on-board I2C bus
# Verified: part0_pins.xml IIC_SCL_MAIN=AM24, IIC_SDA_MAIN=AL24 LVCMOS18
set_property -dict { PACKAGE_PIN AM24 IOSTANDARD LVCMOS18 } [get_ports { i2c_scl }];
set_property -dict { PACKAGE_PIN AL24 IOSTANDARD LVCMOS18 } [get_ports { i2c_sda }];

# -----------------------------------------------------------------------------
# ISP false paths — kept for coralnpu_soc ISP (tied off in chip_vcu118.sv)
# -----------------------------------------------------------------------------
set_false_path -from [get_cells -quiet -hierarchical -filter {NAME =~ *u_isp_regs/*_reg*}] -to [get_cells -quiet -hierarchical -filter {NAME =~ *u_marvin_top*/*_reg* && NAME !~ *u_isp_regs/* && NAME !~ *pvci* && NAME !~ *u_marvin_ctrl*}]
set_false_path -to [get_cells -quiet -hierarchical -filter {NAME =~ *u_isp*/*cfg_mi_rdata_reg*}]
set_false_path -from [get_cells -quiet -hierarchical -filter {NAME =~ *u_marvin_mi*/*_base_ad_reg*}]
set_false_path -from [get_cells -quiet -hierarchical -filter {NAME =~ *u_marvin_mi*/*_size_reg*}]
set_false_path -from [get_cells -quiet -hierarchical -filter {NAME =~ *u_marvin_mi*/*_start_reg*}]

# -----------------------------------------------------------------------------
# Asynchronous Clock Groups
# No ISP_DVP_PCLK group — camera not connected on VCU118
# -----------------------------------------------------------------------------
set_clock_groups -asynchronous \
  -group [get_clocks -include_generated_clocks sys_clk_pin] \
  -group [get_clocks -include_generated_clocks c0_sys_clk_p] \
  -group [get_clocks spi_clk_i] \
  -group [get_clocks jtag_tck_i]

# -----------------------------------------------------------------------------
# DDR4 write data fanout replication (same as Nexus)
# -----------------------------------------------------------------------------
set_property MAX_FANOUT 16 [get_nets -quiet -hierarchical -filter {NAME =~ *USE_UPSIZER.upsizer_d2*wdata*}]
set_property MAX_FANOUT 16 [get_nets -quiet -hierarchical -filter {NAME =~ *USE_UPSIZER.upsizer_d2*wstrb*}]

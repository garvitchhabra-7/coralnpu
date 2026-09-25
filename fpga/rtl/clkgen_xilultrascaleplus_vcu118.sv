// Copyright 2023 Google LLC
// Copyright lowRISC contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// VCU118 variant: 125 MHz input clock (AY24/AY23 LVDS from SI5335A)
// DIVCLK_DIVIDE = 5, CLKFBOUT_MULT_F = 48.0 → VCO = 125 * 48 / 5 = 1200 MHz
module clkgen_xilultrascaleplus_vcu118 #(
    parameter int ClockFrequencyMhz = 50,
    parameter bit AddClkBuf = 1
) (
    input  clk_i,
    input  clk_n_i,
    input  rst_ni,
    input  srst_ni,
    output clk_main_o,
    output clk_isp_o,
    output clk_spim_o,
    output rst_no,
    output locked_o
);
  logic locked_pll;
  logic io_clk_buf;
  logic io_rst_buf_n;
  logic clk_10_buf;
  logic clk_10_unbuf;
  logic clk_fb_buf;
  logic clk_fb_unbuf;
  logic clk_spim_buf;
  logic clk_spim_unbuf;
  logic clk_isp_buf;
  logic clk_isp_unbuf;
  logic clk_ibufds_o;

  IBUFDS clk_ibufds (
      .I (clk_i),
      .IB(clk_n_i),
      .O (clk_ibufds_o)
  );

  localparam real CLKOUT0_DIVIDE_F_RAW = 1200.0 / ClockFrequencyMhz;
  localparam real CLKOUT0_DIVIDE_F_CALC = $rtoi(CLKOUT0_DIVIDE_F_RAW * 8.0 + 0.5) / 8.0;

  MMCME2_ADV #(
      .BANDWIDTH("OPTIMIZED"),
      .COMPENSATION("ZHOLD"),
      .STARTUP_WAIT("FALSE"),
      .DIVCLK_DIVIDE(5),
      .CLKFBOUT_MULT_F(48.000),
      .CLKFBOUT_PHASE(0.000),
      .CLKOUT0_DIVIDE_F(CLKOUT0_DIVIDE_F_CALC),
      .CLKOUT0_PHASE(0.000),
      .CLKOUT0_DUTY_CYCLE(0.500),
      .CLKOUT1_DIVIDE(),
      .CLKOUT1_PHASE(),
      .CLKOUT1_DUTY_CYCLE(),
      .CLKOUT2_DIVIDE(12),
      .CLKOUT2_PHASE(0.000),
      .CLKOUT2_DUTY_CYCLE(0.500),
      .CLKOUT4_DIVIDE(120),
      .CLKOUT4_PHASE(0.000),
      .CLKOUT4_DUTY_CYCLE(0.500),
      .CLKOUT4_CASCADE("FALSE"),
      .CLKOUT6_DIVIDE(120),
      .CLKIN1_PERIOD(8.000)
  ) pll (
      .CLKFBOUT(clk_fb_unbuf),
      .CLKFBOUTB(),
      .CLKOUT0(clk_10_unbuf),
      .CLKOUT0B(),
      .CLKOUT1(),
      .CLKOUT1B(),
      .CLKOUT2(clk_spim_unbuf),
      .CLKOUT2B(),
      .CLKOUT3(),
      .CLKOUT3B(),
      .CLKOUT4(clk_isp_unbuf),
      .CLKOUT5(),
      .CLKOUT6(),
      .CLKFBIN(clk_fb_buf),
      .CLKIN1(clk_ibufds_o),
      .CLKIN2(1'b0),
      .CLKINSEL(1'b1),
      .DADDR(7'h0),
      .DCLK(1'b0),
      .DEN(1'b0),
      .DI(16'h0),
      .DO(),
      .DRDY(),
      .DWE(1'b0),
      .PSCLK(1'b0),
      .PSEN(1'b0),
      .PSINCDEC(1'b0),
      .PSDONE(),
      .CLKFBSTOPPED(),
      .CLKINSTOPPED(),
      .LOCKED(locked_pll),
      .PWRDWN(1'b0),
      .RST(1'b0)
  );

  BUFGCE clk_fb_bufgce (
      .I(clk_fb_unbuf),
      .O(clk_fb_buf)
  );

  BUFGCE clk_spim_bufgce (
      .I(clk_spim_unbuf),
      .O(clk_spim_buf)
  );

  BUFGCE clk_isp_bufgce (
      .I(clk_isp_unbuf),
      .O(clk_isp_buf)
  );

  if (AddClkBuf == 1) begin : gen_clk_bufs
    BUFGCE clk_10_bufgce (
        .I(clk_10_unbuf),
        .O(clk_10_buf)
    );

  end else begin : gen_no_clk_bufs
    assign clk_10_buf = clk_10_unbuf;
  end

  assign clk_main_o = clk_10_buf;
  assign clk_isp_o = clk_isp_buf;
  assign clk_spim_o = clk_spim_buf;

  assign rst_no = locked_pll & rst_ni & srst_ni;
  assign locked_o = locked_pll;
endmodule

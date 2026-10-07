// Copyright 2025 Google LLC
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

module chip_vcu118 #(
    parameter MemInitFile = "",
    parameter int ClockFrequencyMhz = 50,
    parameter int IspClockFrequencyMhz = 10,
    parameter int SpimClockFrequencyMhz = 100,
    parameter int EnableAutoboot = 0,
    parameter int ItcmSizeKBytes = 8,
    parameter int DtcmSizeKBytes = 32,
    parameter int AddrWidth = 32,
    parameter logic [AddrWidth-1:0] BootAddr = 0
) (
    input clk_p_i,
    input clk_n_i,
    input rst_ni,
    input spi_clk_i,
    input spi_csb_i,
    input spi_mosi_i,
    output logic spi_miso_o,
    output logic spim_sclk_o,
    output logic spim_csb_o,
    output logic spim_mosi_o,
    input spim_miso_i,
    // SPI flash ports removed: VCU118 has no flash wired and PMOD0 has no pins
    // left for CS/RESET. The SPI flash master is tied off below (ROM boot unused).
    // GPIO removed: VCU118 DIP switches are in HP banks (72/73) which don't support LVCMOS12.
    output [1 : 0] uart_tx_o,
    input [1 : 0] uart_rx_i,
    inout wire i2c_scl,
    inout wire i2c_sda,
    output logic io_halted,
    output logic io_fault,
    output logic io_ddr_mem_axi_aw_ready,
    output logic io_ddr_mem_axi_ar_ready,
    output logic c0_ddr4_act_n,
    output logic [16:0] c0_ddr4_adr,
    output logic [1:0] c0_ddr4_ba,
    output logic [0:0] c0_ddr4_bg,
    output logic [0:0] c0_ddr4_cke,
    output logic [0:0] c0_ddr4_odt,
    output logic [0:0] c0_ddr4_cs_n,
    output logic [0:0] c0_ddr4_ck_t,
    output logic [0:0] c0_ddr4_ck_c,
    output logic c0_ddr4_reset_n,
    inout wire [7:0] c0_ddr4_dm_n,
    inout wire [63:0] c0_ddr4_dq,
    inout wire [7:0] c0_ddr4_dqs_c,
    inout wire [7:0] c0_ddr4_dqs_t,
    input logic c0_sys_clk_p,
    input logic c0_sys_clk_n,
    output logic ddr_cal_complete_o,
    output ddr_ui_clk,
    output ddr_ui_clk_sync_rst,
    input tck_i,
    input tms_i,
    input trst_ni,
    input td_i,
    output td_o
);

  // VCU118 CPU_RESET (L19) is an active-HIGH push button (board.xml rst_polarity=1,
  // "CPU Reset Push Button, Active High"). Invert at the pad so the rest of the design
  // sees an active-low reset, matching chip_nexus.sv conventions.
  logic rst_n_pad;
  assign rst_n_pad = ~rst_ni;

  logic clk;
  logic rst_n;
  logic clk_isp;
  logic clk_spim;
  logic locked;
  logic eos;
  logic mig_sys_rst;
  logic c0_init_calib_complete;
  logic c0_ddr4_ui_clk;
  logic c0_ddr4_ui_clk_sync_rst;

  assign ddr_ui_clk = c0_ddr4_ui_clk;
  assign ddr_ui_clk_sync_rst = c0_ddr4_ui_clk_sync_rst;

  // The SoC's DDR-side logic runs on the MIG's 100 MHz addn_ui_clkout1, not on
  // the 300 MHz UI clock. The SmartConnect in ddr_system_bd converts to the UI
  // clock (S00 on aclk1, M00 on aclk). ddr_axi_rst is the UI-clock reset,
  // asserted asynchronously and released synchronously to ddr_axi_clk.
  logic ddr_axi_clk;
  logic ddr_axi_rst;
  (* ASYNC_REG = "TRUE" *) logic [2:0] ddr_axi_rst_q;

  always_ff @(posedge ddr_axi_clk or posedge c0_ddr4_ui_clk_sync_rst) begin
    if (c0_ddr4_ui_clk_sync_rst) begin
      ddr_axi_rst_q <= '1;
    end else begin
      ddr_axi_rst_q <= {ddr_axi_rst_q[1:0], 1'b0};
    end
  end
  assign ddr_axi_rst = ddr_axi_rst_q[2];

  // MIG wrapper exposes bg[1:0] but only bg[0] is connected (single bank group memory).
  wire [1:0] c0_ddr4_bg_internal;
  assign c0_ddr4_bg = c0_ddr4_bg_internal[0];

  //================================================================
  //== STARTUPE3 Primitive for reliable FPGA startup
  //================================================================
  STARTUPE3 i_startupe3 (
      .EOS(eos),
      // --- Unused ports, connect to dummy wires or tie off ---
      .CFGCLK(),
      .CFGMCLK(),
      .PREQ(),
      // --- Tie off unused inputs ---
      .GSR(1'b0),
      .GTS(1'b0),
      .KEYCLEARB(1'b0),
      .PACK(1'b0),
      .USRCCLKO(1'b0),
      .USRCCLKTS(1'b0),
      .USRDONEO(1'b0),
      .USRDONETS(1'b0)
  );

  //================================================================
  //== Combined Reset Logic for DDR4 MIG
  //================================================================
  assign mig_sys_rst = (~locked) | (~eos) | (~rst_n_pad);

  top_pkg::uart_sideband_i_t [1 : 0] uart_sideband_i;
  top_pkg::uart_sideband_o_t [1 : 0] uart_sideband_o;

  assign uart_sideband_i[0].cio_rx = uart_rx_i[0];
  assign uart_sideband_i[1].cio_rx = uart_rx_i[1];
  assign uart_tx_o[0] = uart_sideband_o[0].cio_tx;
  assign uart_tx_o[1] = uart_sideband_o[1].cio_tx;

  wire [7:0] gpio_out;
  wire [7:0] gpio_en;
  wire [7:0] gpio_in;

  // gpio_in[0] = DDR calibration done, so software can wait for it before
  // touching 0x80000000 (an access before calibration hangs the crossbar).
  // c0_init_calib_complete is in the MIG UI clock domain; the GPIO block
  // samples gpio_i directly, so synchronise it to clk here.
  (* ASYNC_REG = "TRUE" *) logic [1:0] ddr_cal_sync_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ddr_cal_sync_q <= '0;
    end else begin
      ddr_cal_sync_q <= {ddr_cal_sync_q[0], c0_init_calib_complete};
    end
  end
  assign gpio_in = {7'b0, ddr_cal_sync_q[1]};

  logic scl_in, scl_out, scl_en;
  logic sda_in, sda_out, sda_en;

  IOBUF i_scl_iobuf (
      .O (scl_in),
      .IO(i2c_scl),
      .I (scl_out),
      .T (~scl_en)
  );
  IOBUF i_sda_iobuf (
      .O (sda_in),
      .IO(i2c_sda),
      .I (sda_out),
      .T (~sda_en)
  );

  assign ddr_cal_complete_o = c0_init_calib_complete;
  logic c0_ddr4_aresetn;
  logic [0:0] c0_ddr4_s_axi_awid;
  logic [33:0] c0_ddr4_s_axi_awaddr;
  logic [AddrWidth-1:0] soc_ddr_mem_axi_aw_bits_addr;
  logic [AddrWidth-1:0] soc_ddr_mem_axi_ar_bits_addr;
  logic [7:0] c0_ddr4_s_axi_awlen;
  logic [2:0] c0_ddr4_s_axi_awsize;
  logic [1:0] c0_ddr4_s_axi_awburst;
  logic [0:0] c0_ddr4_s_axi_awlock;
  logic [3:0] c0_ddr4_s_axi_awcache;
  logic [2:0] c0_ddr4_s_axi_awprot;
  logic [3:0] c0_ddr4_s_axi_awqos;
  logic c0_ddr4_s_axi_awvalid;
  logic c0_ddr4_s_axi_awready;
  logic [255:0] c0_ddr4_s_axi_wdata;
  logic [31:0] c0_ddr4_s_axi_wstrb;
  logic c0_ddr4_s_axi_wlast;
  logic c0_ddr4_s_axi_wvalid;
  logic c0_ddr4_s_axi_wready;
  logic c0_ddr4_s_axi_bready;
  logic [0:0] c0_ddr4_s_axi_bid;
  logic [1:0] c0_ddr4_s_axi_bresp;
  logic c0_ddr4_s_axi_bvalid;
  logic [0:0] c0_ddr4_s_axi_arid;
  logic [33:0] c0_ddr4_s_axi_araddr;
  logic [7:0] c0_ddr4_s_axi_arlen;
  logic [2:0] c0_ddr4_s_axi_arsize;
  logic [1:0] c0_ddr4_s_axi_arburst;
  logic [0:0] c0_ddr4_s_axi_arlock;
  logic [3:0] c0_ddr4_s_axi_arcache;
  logic [2:0] c0_ddr4_s_axi_arprot;
  logic [3:0] c0_ddr4_s_axi_arqos;
  logic c0_ddr4_s_axi_arvalid;
  logic c0_ddr4_s_axi_arready;
  logic c0_ddr4_s_axi_rready;
  logic [0:0] c0_ddr4_s_axi_rid;
  logic [255:0] c0_ddr4_s_axi_rdata;
  logic [1:0] c0_ddr4_s_axi_rresp;
  logic c0_ddr4_s_axi_rlast;
  logic c0_ddr4_s_axi_rvalid;
  assign io_ddr_mem_axi_aw_ready = c0_ddr4_s_axi_awready;
  assign io_ddr_mem_axi_ar_ready = c0_ddr4_s_axi_arready;
  assign c0_ddr4_aresetn = ~c0_ddr4_ui_clk_sync_rst;

  // DDR4 ctrl AXI — not exposed by the block design wrapper (no ECC).
  // Tie off the SoC-side ctrl port: ready for writes, no read data.
  logic c0_ddr4_s_axi_ctrl_awready;
  logic c0_ddr4_s_axi_ctrl_wready;
  logic c0_ddr4_s_axi_ctrl_bvalid;
  logic [1:0] c0_ddr4_s_axi_ctrl_bresp;
  logic c0_ddr4_s_axi_ctrl_arready;
  logic c0_ddr4_s_axi_ctrl_rvalid;
  logic [31:0] c0_ddr4_s_axi_ctrl_rdata;
  logic [1:0] c0_ddr4_s_axi_ctrl_rresp;
  assign c0_ddr4_s_axi_ctrl_awready = 1'b0;
  assign c0_ddr4_s_axi_ctrl_wready = 1'b0;
  assign c0_ddr4_s_axi_ctrl_bvalid = 1'b0;
  assign c0_ddr4_s_axi_ctrl_bresp = 2'b00;
  assign c0_ddr4_s_axi_ctrl_arready = 1'b0;
  assign c0_ddr4_s_axi_ctrl_rvalid = 1'b0;
  assign c0_ddr4_s_axi_ctrl_rdata = 32'b0;
  assign c0_ddr4_s_axi_ctrl_rresp = 2'b00;

  ddr_system_bd_wrapper i_ddr4 (
      .sys_rst_0(mig_sys_rst),
      .C0_SYS_CLK_0_clk_p(c0_sys_clk_p),
      .C0_SYS_CLK_0_clk_n(c0_sys_clk_n),
      .C0_DDR4_0_act_n(c0_ddr4_act_n),
      .C0_DDR4_0_adr(c0_ddr4_adr),
      .C0_DDR4_0_ba(c0_ddr4_ba),
      .C0_DDR4_0_bg(c0_ddr4_bg_internal),
      .C0_DDR4_0_cke(c0_ddr4_cke),
      .C0_DDR4_0_odt(c0_ddr4_odt),
      .C0_DDR4_0_cs_n(c0_ddr4_cs_n),
      .C0_DDR4_0_ck_t(c0_ddr4_ck_t),
      .C0_DDR4_0_ck_c(c0_ddr4_ck_c),
      .C0_DDR4_0_reset_n(c0_ddr4_reset_n),
      .C0_DDR4_0_dm_n(c0_ddr4_dm_n),
      .C0_DDR4_0_dq(c0_ddr4_dq),
      .C0_DDR4_0_dqs_c(c0_ddr4_dqs_c),
      .C0_DDR4_0_dqs_t(c0_ddr4_dqs_t),
      .c0_init_calib_complete_0(c0_init_calib_complete),
      .c0_ddr4_ui_clk_0(c0_ddr4_ui_clk),
      .c0_ddr4_ui_clk_sync_rst_0(c0_ddr4_ui_clk_sync_rst),
      .c0_ddr4_aresetn_0(c0_ddr4_aresetn),
      .addn_ui_clkout1_0(ddr_axi_clk),
      .dbg_clk_0(),
      .dbg_bus_0(),
      .S00_AXI_0_awid(c0_ddr4_s_axi_awid),
      .S00_AXI_0_awaddr(c0_ddr4_s_axi_awaddr),
      .S00_AXI_0_awlen(c0_ddr4_s_axi_awlen),
      .S00_AXI_0_awsize(c0_ddr4_s_axi_awsize),
      .S00_AXI_0_awburst(c0_ddr4_s_axi_awburst),
      .S00_AXI_0_awlock(c0_ddr4_s_axi_awlock),
      .S00_AXI_0_awcache(c0_ddr4_s_axi_awcache),
      .S00_AXI_0_awprot(c0_ddr4_s_axi_awprot),
      .S00_AXI_0_awqos(c0_ddr4_s_axi_awqos),
      .S00_AXI_0_awvalid(c0_ddr4_s_axi_awvalid),
      .S00_AXI_0_awready(c0_ddr4_s_axi_awready),
      .S00_AXI_0_wdata(c0_ddr4_s_axi_wdata),
      .S00_AXI_0_wstrb(c0_ddr4_s_axi_wstrb),
      .S00_AXI_0_wlast(c0_ddr4_s_axi_wlast),
      .S00_AXI_0_wvalid(c0_ddr4_s_axi_wvalid),
      .S00_AXI_0_wready(c0_ddr4_s_axi_wready),
      .S00_AXI_0_bready(c0_ddr4_s_axi_bready),
      .S00_AXI_0_bid(c0_ddr4_s_axi_bid),
      .S00_AXI_0_bresp(c0_ddr4_s_axi_bresp),
      .S00_AXI_0_bvalid(c0_ddr4_s_axi_bvalid),
      .S00_AXI_0_arid(c0_ddr4_s_axi_arid),
      .S00_AXI_0_araddr(c0_ddr4_s_axi_araddr),
      .S00_AXI_0_arlen(c0_ddr4_s_axi_arlen),
      .S00_AXI_0_arsize(c0_ddr4_s_axi_arsize),
      .S00_AXI_0_arburst(c0_ddr4_s_axi_arburst),
      .S00_AXI_0_arlock(c0_ddr4_s_axi_arlock),
      .S00_AXI_0_arcache(c0_ddr4_s_axi_arcache),
      .S00_AXI_0_arprot(c0_ddr4_s_axi_arprot),
      .S00_AXI_0_arqos(c0_ddr4_s_axi_arqos),
      .S00_AXI_0_arvalid(c0_ddr4_s_axi_arvalid),
      .S00_AXI_0_arready(c0_ddr4_s_axi_arready),
      .S00_AXI_0_rready(c0_ddr4_s_axi_rready),
      .S00_AXI_0_rid(c0_ddr4_s_axi_rid),
      .S00_AXI_0_rdata(c0_ddr4_s_axi_rdata),
      .S00_AXI_0_rresp(c0_ddr4_s_axi_rresp),
      .S00_AXI_0_rlast(c0_ddr4_s_axi_rlast),
      .S00_AXI_0_rvalid(c0_ddr4_s_axi_rvalid)
  );

  clkgen_wrapper #(
      .ClockFrequencyMhz(ClockFrequencyMhz)
  ) i_clkgen (
      .clk_p_i(clk_p_i),
      .clk_n_i(clk_n_i),
      .rst_ni(rst_n_pad),
      .srst_ni(rst_n_pad),
      .clk_main_o(clk),
      .clk_isp_o(clk_isp),
      .clk_spim_o(clk_spim),
      .rst_no(rst_n),
      .locked_o(locked)
  );

  logic dm_req_valid, dm_req_ready;
  dm::dmi_req_t dm_req;
  logic dm_rsp_valid, dm_rsp_ready;
  dm::dmi_resp_t dm_rsp;
  logic dmi_rst_n;

  dmi_jtag #(
      .IdcodeValue(32'h04f5484d)
  ) i_jtag (
      .clk_i(clk),
      .rst_ni(rst_n),
      .testmode_i(1'b0),
      .test_rst_ni(1'b1),
      .dmi_rst_no(dmi_rst_n),
      .dmi_req_o(dm_req),
      .dmi_req_valid_o(dm_req_valid),
      .dmi_req_ready_i(dm_req_ready),
      .dmi_resp_i(dm_rsp),
      .dmi_resp_ready_o(dm_rsp_ready),
      .dmi_resp_valid_i(dm_rsp_valid),
      .tck_i(tck_i),
      .tms_i(tms_i),
      .trst_ni(trst_ni),
      .td_i(td_i),
      .td_o(td_o),
      .tdo_oe_o(  /*tdo_oe_o*/)
  );

  coralnpu_soc #(
      .MemInitFile(MemInitFile),
      .ClockFrequencyMhz(ClockFrequencyMhz),
      .IspClockFrequencyMhz(IspClockFrequencyMhz),
      .SpimClockFrequencyMhz(SpimClockFrequencyMhz),
      .EnableAutoboot(EnableAutoboot),
      .ItcmSizeKBytes(ItcmSizeKBytes),
      .DtcmSizeKBytes(DtcmSizeKBytes),
      .AddrWidth(AddrWidth)
  ) i_coralnpu_soc (
      .clk_i(clk),
      .clk_isp_i(clk_isp),
      .rst_ni(rst_n),
      .spi_clk_i(spi_clk_i),
      .spi_csb_i(spi_csb_i),
      .spi_mosi_i(spi_mosi_i),
      .spi_miso_o(spi_miso_o),
      .spim_sclk_o(spim_sclk_o),
      .spim_csb_o(spim_csb_o),
      .spim_mosi_o(spim_mosi_o),
      .spim_miso_i(spim_miso_i),
      .spim_clk_i(clk_spim),
      .boot_addr_i(BootAddr),
      .spim_flash_sclk_o(),
      .spim_flash_csb_o(),
      .spim_flash_mosi_o(),
      .spim_flash_miso_i(1'b1),
      .spim_flash_clk_i(clk_spim),
      .spim_flash_rst_no(),
      .gpio_o(gpio_out),
      .gpio_en_o(gpio_en),
      .gpio_i(gpio_in),
      // Camera/ISP tied off — no camera in VCU118 demo
      .ISP_DVP_D0(1'b0),
      .ISP_DVP_D1(1'b0),
      .ISP_DVP_D2(1'b0),
      .ISP_DVP_D3(1'b0),
      .ISP_DVP_D4(1'b0),
      .ISP_DVP_D5(1'b0),
      .ISP_DVP_D6(1'b0),
      .ISP_DVP_D7(1'b0),
      .ISP_DVP_PCLK(1'b0),
      .ISP_DVP_HSYNC(1'b0),
      .ISP_DVP_VSYNC(1'b0),
      .CAM_INT(1'b0),
      .CAM_TRIG(),
      .scanmode_i('0),
      .uart_sideband_i(uart_sideband_i),
      .uart_sideband_o(uart_sideband_o),
      .scl_i(scl_in),
      .scl_o(scl_out),
      .scl_en_o(scl_en),
      .sda_i(sda_in),
      .sda_o(sda_out),
      .sda_en_o(sda_en),
      .io_halted(io_halted),
      .io_fault(io_fault),
      .ddr_clk_i(ddr_axi_clk),
      .ddr_rst(ddr_axi_rst),
      .io_ddr_ctrl_axi_aw_valid(c0_ddr4_s_axi_ctrl_awvalid),
      .io_ddr_ctrl_axi_aw_ready(c0_ddr4_s_axi_ctrl_awready),
      .io_ddr_ctrl_axi_aw_bits_addr(c0_ddr4_s_axi_ctrl_awaddr),
      .io_ddr_ctrl_axi_w_valid(c0_ddr4_s_axi_ctrl_wvalid),
      .io_ddr_ctrl_axi_w_ready(c0_ddr4_s_axi_ctrl_wready),
      .io_ddr_ctrl_axi_w_bits_data(c0_ddr4_s_axi_ctrl_wdata),
      .io_ddr_ctrl_axi_b_valid(c0_ddr4_s_axi_ctrl_bvalid),
      .io_ddr_ctrl_axi_b_ready(c0_ddr4_s_axi_ctrl_bready),
      .io_ddr_ctrl_axi_b_bits_resp(c0_ddr4_s_axi_ctrl_bresp),
      .io_ddr_ctrl_axi_ar_valid(c0_ddr4_s_axi_ctrl_arvalid),
      .io_ddr_ctrl_axi_ar_ready(c0_ddr4_s_axi_ctrl_arready),
      .io_ddr_ctrl_axi_ar_bits_addr(c0_ddr4_s_axi_ctrl_araddr),
      .io_ddr_ctrl_axi_r_valid(c0_ddr4_s_axi_ctrl_rvalid),
      .io_ddr_ctrl_axi_r_ready(c0_ddr4_s_axi_ctrl_rready),
      .io_ddr_ctrl_axi_r_bits_data(c0_ddr4_s_axi_ctrl_rdata),
      .io_ddr_ctrl_axi_r_bits_resp(c0_ddr4_s_axi_ctrl_rresp),
      .io_ddr_mem_axi_aw_valid(c0_ddr4_s_axi_awvalid),
      .io_ddr_mem_axi_aw_ready(c0_ddr4_s_axi_awready),
      .io_ddr_mem_axi_aw_bits_addr(soc_ddr_mem_axi_aw_bits_addr),
      .io_ddr_mem_axi_aw_bits_prot(c0_ddr4_s_axi_awprot),
      .io_ddr_mem_axi_aw_bits_id(c0_ddr4_s_axi_awid),
      .io_ddr_mem_axi_aw_bits_len(c0_ddr4_s_axi_awlen),
      .io_ddr_mem_axi_aw_bits_size(c0_ddr4_s_axi_awsize),
      .io_ddr_mem_axi_aw_bits_burst(c0_ddr4_s_axi_awburst),
      .io_ddr_mem_axi_aw_bits_lock(c0_ddr4_s_axi_awlock),
      .io_ddr_mem_axi_aw_bits_cache(c0_ddr4_s_axi_awcache),
      .io_ddr_mem_axi_aw_bits_qos(c0_ddr4_s_axi_awqos),
      .io_ddr_mem_axi_w_valid(c0_ddr4_s_axi_wvalid),
      .io_ddr_mem_axi_w_ready(c0_ddr4_s_axi_wready),
      .io_ddr_mem_axi_w_bits_data(c0_ddr4_s_axi_wdata),
      .io_ddr_mem_axi_w_bits_last(c0_ddr4_s_axi_wlast),
      .io_ddr_mem_axi_w_bits_strb(c0_ddr4_s_axi_wstrb),
      .io_ddr_mem_axi_b_valid(c0_ddr4_s_axi_bvalid),
      .io_ddr_mem_axi_b_ready(c0_ddr4_s_axi_bready),
      .io_ddr_mem_axi_b_bits_id(c0_ddr4_s_axi_bid),
      .io_ddr_mem_axi_b_bits_resp(c0_ddr4_s_axi_bresp),
      .io_ddr_mem_axi_ar_valid(c0_ddr4_s_axi_arvalid),
      .io_ddr_mem_axi_ar_ready(c0_ddr4_s_axi_arready),
      .io_ddr_mem_axi_ar_bits_addr(soc_ddr_mem_axi_ar_bits_addr),
      .io_ddr_mem_axi_ar_bits_prot(c0_ddr4_s_axi_arprot),
      .io_ddr_mem_axi_ar_bits_id(c0_ddr4_s_axi_arid),
      .io_ddr_mem_axi_ar_bits_len(c0_ddr4_s_axi_arlen),
      .io_ddr_mem_axi_ar_bits_size(c0_ddr4_s_axi_arsize),
      .io_ddr_mem_axi_ar_bits_burst(c0_ddr4_s_axi_arburst),
      .io_ddr_mem_axi_ar_bits_lock(c0_ddr4_s_axi_arlock),
      .io_ddr_mem_axi_ar_bits_cache(c0_ddr4_s_axi_arcache),
      .io_ddr_mem_axi_ar_bits_qos(c0_ddr4_s_axi_arqos),
      .io_ddr_mem_axi_r_valid(c0_ddr4_s_axi_rvalid),
      .io_ddr_mem_axi_r_ready(c0_ddr4_s_axi_rready),
      .io_ddr_mem_axi_r_bits_data(c0_ddr4_s_axi_rdata),
      .io_ddr_mem_axi_r_bits_id(c0_ddr4_s_axi_rid),
      .io_ddr_mem_axi_r_bits_resp(c0_ddr4_s_axi_rresp),
      .io_ddr_mem_axi_r_bits_last(c0_ddr4_s_axi_rlast),
      .io_dm_req_valid(dm_req_valid),
      .io_dm_req_ready(dm_req_ready),
      .io_dm_req_bits_address(dm_req.addr),
      .io_dm_req_bits_data(dm_req.data),
      .io_dm_req_bits_op(dm_req.op),
      .io_dm_rsp_ready(dm_rsp_ready),
      .io_dm_rsp_valid(dm_rsp_valid),
      .io_dm_rsp_bits_data(dm_rsp.data),
      .io_dm_rsp_bits_op(dm_rsp.resp)
  );

  assign c0_ddr4_s_axi_awaddr = 34'(soc_ddr_mem_axi_aw_bits_addr);
  assign c0_ddr4_s_axi_araddr = 34'(soc_ddr_mem_axi_ar_bits_addr);

endmodule

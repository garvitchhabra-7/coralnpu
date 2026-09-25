//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2 (lin64) Build 6299465 Fri Nov 14 12:34:56 MST 2025
//Date        : Tue Sep 22 13:46:01 2026
//Host        : synthesia running 64-bit Rocky Linux release 8.10 (Green Obsidian)
//Command     : generate_target ddr_system_bd.bd
//Design      : ddr_system_bd
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "ddr_system_bd,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=ddr_system_bd,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=2,numReposBlks=2,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=0,numPkgbdBlks=0,bdsource=USER,synth_mode=Hierarchical}" *) (* HW_HANDOFF = "ddr_system_bd.hwdef" *) 
module ddr_system_bd
   (C0_DDR4_0_act_n,
    C0_DDR4_0_adr,
    C0_DDR4_0_ba,
    C0_DDR4_0_bg,
    C0_DDR4_0_ck_c,
    C0_DDR4_0_ck_t,
    C0_DDR4_0_cke,
    C0_DDR4_0_cs_n,
    C0_DDR4_0_dm_n,
    C0_DDR4_0_dq,
    C0_DDR4_0_dqs_c,
    C0_DDR4_0_dqs_t,
    C0_DDR4_0_odt,
    C0_DDR4_0_reset_n,
    C0_SYS_CLK_0_clk_n,
    C0_SYS_CLK_0_clk_p,
    S00_AXI_0_araddr,
    S00_AXI_0_arburst,
    S00_AXI_0_arcache,
    S00_AXI_0_arid,
    S00_AXI_0_arlen,
    S00_AXI_0_arlock,
    S00_AXI_0_arprot,
    S00_AXI_0_arqos,
    S00_AXI_0_arready,
    S00_AXI_0_arsize,
    S00_AXI_0_arvalid,
    S00_AXI_0_awaddr,
    S00_AXI_0_awburst,
    S00_AXI_0_awcache,
    S00_AXI_0_awid,
    S00_AXI_0_awlen,
    S00_AXI_0_awlock,
    S00_AXI_0_awprot,
    S00_AXI_0_awqos,
    S00_AXI_0_awready,
    S00_AXI_0_awsize,
    S00_AXI_0_awvalid,
    S00_AXI_0_bid,
    S00_AXI_0_bready,
    S00_AXI_0_bresp,
    S00_AXI_0_bvalid,
    S00_AXI_0_rdata,
    S00_AXI_0_rid,
    S00_AXI_0_rlast,
    S00_AXI_0_rready,
    S00_AXI_0_rresp,
    S00_AXI_0_rvalid,
    S00_AXI_0_wdata,
    S00_AXI_0_wlast,
    S00_AXI_0_wready,
    S00_AXI_0_wstrb,
    S00_AXI_0_wvalid,
    addn_ui_clkout1_0,
    c0_ddr4_aresetn_0,
    c0_ddr4_ui_clk_0,
    c0_ddr4_ui_clk_sync_rst_0,
    c0_init_calib_complete_0,
    dbg_bus_0,
    dbg_clk_0,
    sys_rst_0);
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 ACT_N" *) (* X_INTERFACE_MODE = "Master" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME C0_DDR4_0, AXI_ARBITRATION_SCHEME RD_PRI_REG, BURST_LENGTH 8, CAN_DEBUG false, CAS_LATENCY 18, CAS_WRITE_LATENCY 12, CS_ENABLED true, CUSTOM_PARTS no_file_loaded, DATA_MASK_ENABLED DM_NO_DBI, DATA_WIDTH 64, MEMORY_PART MT40A256M16LY-062E, MEMORY_TYPE Components, MEM_ADDR_MAP ROW_COLUMN_BANK, SLOT Single, TIMEPERIOD_PS 833" *) output C0_DDR4_0_act_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 ADR" *) output [16:0]C0_DDR4_0_adr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 BA" *) output [1:0]C0_DDR4_0_ba;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 BG" *) output [1:0]C0_DDR4_0_bg;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 CK_C" *) output [0:0]C0_DDR4_0_ck_c;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 CK_T" *) output [0:0]C0_DDR4_0_ck_t;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 CKE" *) output [0:0]C0_DDR4_0_cke;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 CS_N" *) output [0:0]C0_DDR4_0_cs_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 DM_N" *) inout [7:0]C0_DDR4_0_dm_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 DQ" *) inout [63:0]C0_DDR4_0_dq;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 DQS_C" *) inout [7:0]C0_DDR4_0_dqs_c;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 DQS_T" *) inout [7:0]C0_DDR4_0_dqs_t;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 ODT" *) output [0:0]C0_DDR4_0_odt;
  (* X_INTERFACE_INFO = "xilinx.com:interface:ddr4:1.0 C0_DDR4_0 RESET_N" *) output C0_DDR4_0_reset_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock:1.0 C0_SYS_CLK_0 CLK_N" *) (* X_INTERFACE_MODE = "Slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME C0_SYS_CLK_0, CAN_DEBUG false, FREQ_HZ 250000000" *) input C0_SYS_CLK_0_clk_n;
  (* X_INTERFACE_INFO = "xilinx.com:interface:diff_clock:1.0 C0_SYS_CLK_0 CLK_P" *) input C0_SYS_CLK_0_clk_p;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARADDR" *) (* X_INTERFACE_MODE = "Slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S00_AXI_0, ADDR_WIDTH 34, ARUSER_WIDTH 0, AWUSER_WIDTH 0, BUSER_WIDTH 0, DATA_WIDTH 256, FREQ_HZ 300000000, HAS_BRESP 1, HAS_BURST 1, HAS_CACHE 1, HAS_LOCK 1, HAS_PROT 1, HAS_QOS 1, HAS_REGION 1, HAS_RRESP 1, HAS_WSTRB 1, ID_WIDTH 1, INSERT_VIP 0, MAX_BURST_LENGTH 256, NUM_READ_OUTSTANDING 1, NUM_READ_THREADS 1, NUM_WRITE_OUTSTANDING 1, NUM_WRITE_THREADS 1, PHASE 0.0, PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, RUSER_BITS_PER_BYTE 0, RUSER_WIDTH 0, SUPPORTS_NARROW_BURST 1, WUSER_BITS_PER_BYTE 0, WUSER_WIDTH 0" *) input [33:0]S00_AXI_0_araddr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARBURST" *) input [1:0]S00_AXI_0_arburst;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARCACHE" *) input [3:0]S00_AXI_0_arcache;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARID" *) input [0:0]S00_AXI_0_arid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARLEN" *) input [7:0]S00_AXI_0_arlen;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARLOCK" *) input [0:0]S00_AXI_0_arlock;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARPROT" *) input [2:0]S00_AXI_0_arprot;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARQOS" *) input [3:0]S00_AXI_0_arqos;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARREADY" *) output S00_AXI_0_arready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARSIZE" *) input [2:0]S00_AXI_0_arsize;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 ARVALID" *) input S00_AXI_0_arvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWADDR" *) input [33:0]S00_AXI_0_awaddr;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWBURST" *) input [1:0]S00_AXI_0_awburst;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWCACHE" *) input [3:0]S00_AXI_0_awcache;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWID" *) input [0:0]S00_AXI_0_awid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWLEN" *) input [7:0]S00_AXI_0_awlen;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWLOCK" *) input [0:0]S00_AXI_0_awlock;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWPROT" *) input [2:0]S00_AXI_0_awprot;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWQOS" *) input [3:0]S00_AXI_0_awqos;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWREADY" *) output S00_AXI_0_awready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWSIZE" *) input [2:0]S00_AXI_0_awsize;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 AWVALID" *) input S00_AXI_0_awvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 BID" *) output [0:0]S00_AXI_0_bid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 BREADY" *) input S00_AXI_0_bready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 BRESP" *) output [1:0]S00_AXI_0_bresp;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 BVALID" *) output S00_AXI_0_bvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 RDATA" *) output [255:0]S00_AXI_0_rdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 RID" *) output [0:0]S00_AXI_0_rid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 RLAST" *) output S00_AXI_0_rlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 RREADY" *) input S00_AXI_0_rready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 RRESP" *) output [1:0]S00_AXI_0_rresp;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 RVALID" *) output S00_AXI_0_rvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 WDATA" *) input [255:0]S00_AXI_0_wdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 WLAST" *) input S00_AXI_0_wlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 WREADY" *) output S00_AXI_0_wready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 WSTRB" *) input [31:0]S00_AXI_0_wstrb;
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI_0 WVALID" *) input S00_AXI_0_wvalid;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.ADDN_UI_CLKOUT1_0 CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.ADDN_UI_CLKOUT1_0, CLK_DOMAIN ddr_system_bd_ddr4_0_0_c0_ddr4_ui_clk, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0" *) output addn_ui_clkout1_0;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.C0_DDR4_ARESETN_0 RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.C0_DDR4_ARESETN_0, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input c0_ddr4_aresetn_0;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.C0_DDR4_UI_CLK_0 CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.C0_DDR4_UI_CLK_0, CLK_DOMAIN ddr_system_bd_ddr4_0_0_c0_ddr4_ui_clk, FREQ_HZ 300000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.00" *) output c0_ddr4_ui_clk_0;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.C0_DDR4_UI_CLK_SYNC_RST_0 RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.C0_DDR4_UI_CLK_SYNC_RST_0, INSERT_VIP 0, POLARITY ACTIVE_HIGH" *) output c0_ddr4_ui_clk_sync_rst_0;
  output c0_init_calib_complete_0;
  output [511:0]dbg_bus_0;
  output dbg_clk_0;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.SYS_RST_0 RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.SYS_RST_0, INSERT_VIP 0, POLARITY ACTIVE_HIGH" *) input sys_rst_0;

  wire C0_DDR4_0_act_n;
  wire [16:0]C0_DDR4_0_adr;
  wire [1:0]C0_DDR4_0_ba;
  wire [1:0]C0_DDR4_0_bg;
  wire [0:0]C0_DDR4_0_ck_c;
  wire [0:0]C0_DDR4_0_ck_t;
  wire [0:0]C0_DDR4_0_cke;
  wire [0:0]C0_DDR4_0_cs_n;
  wire [7:0]C0_DDR4_0_dm_n;
  wire [63:0]C0_DDR4_0_dq;
  wire [7:0]C0_DDR4_0_dqs_c;
  wire [7:0]C0_DDR4_0_dqs_t;
  wire [0:0]C0_DDR4_0_odt;
  wire C0_DDR4_0_reset_n;
  wire C0_SYS_CLK_0_clk_n;
  wire C0_SYS_CLK_0_clk_p;
  wire [33:0]S00_AXI_0_araddr;
  wire [1:0]S00_AXI_0_arburst;
  wire [3:0]S00_AXI_0_arcache;
  wire [0:0]S00_AXI_0_arid;
  wire [7:0]S00_AXI_0_arlen;
  wire [0:0]S00_AXI_0_arlock;
  wire [2:0]S00_AXI_0_arprot;
  wire [3:0]S00_AXI_0_arqos;
  wire S00_AXI_0_arready;
  wire [2:0]S00_AXI_0_arsize;
  wire S00_AXI_0_arvalid;
  wire [33:0]S00_AXI_0_awaddr;
  wire [1:0]S00_AXI_0_awburst;
  wire [3:0]S00_AXI_0_awcache;
  wire [0:0]S00_AXI_0_awid;
  wire [7:0]S00_AXI_0_awlen;
  wire [0:0]S00_AXI_0_awlock;
  wire [2:0]S00_AXI_0_awprot;
  wire [3:0]S00_AXI_0_awqos;
  wire S00_AXI_0_awready;
  wire [2:0]S00_AXI_0_awsize;
  wire S00_AXI_0_awvalid;
  wire [0:0]S00_AXI_0_bid;
  wire S00_AXI_0_bready;
  wire [1:0]S00_AXI_0_bresp;
  wire S00_AXI_0_bvalid;
  wire [255:0]S00_AXI_0_rdata;
  wire [0:0]S00_AXI_0_rid;
  wire S00_AXI_0_rlast;
  wire S00_AXI_0_rready;
  wire [1:0]S00_AXI_0_rresp;
  wire S00_AXI_0_rvalid;
  wire [255:0]S00_AXI_0_wdata;
  wire S00_AXI_0_wlast;
  wire S00_AXI_0_wready;
  wire [31:0]S00_AXI_0_wstrb;
  wire S00_AXI_0_wvalid;
  wire addn_ui_clkout1_0;
  wire c0_ddr4_aresetn_0;
  wire c0_ddr4_ui_clk_0;
  wire c0_ddr4_ui_clk_sync_rst_0;
  wire c0_init_calib_complete_0;
  wire [511:0]dbg_bus_0;
  wire dbg_clk_0;
  wire [30:0]smartconnect_0_M00_AXI_ARADDR;
  wire [1:0]smartconnect_0_M00_AXI_ARBURST;
  wire [3:0]smartconnect_0_M00_AXI_ARCACHE;
  wire [7:0]smartconnect_0_M00_AXI_ARLEN;
  wire [0:0]smartconnect_0_M00_AXI_ARLOCK;
  wire [2:0]smartconnect_0_M00_AXI_ARPROT;
  wire [3:0]smartconnect_0_M00_AXI_ARQOS;
  wire smartconnect_0_M00_AXI_ARREADY;
  wire [2:0]smartconnect_0_M00_AXI_ARSIZE;
  wire smartconnect_0_M00_AXI_ARVALID;
  wire [30:0]smartconnect_0_M00_AXI_AWADDR;
  wire [1:0]smartconnect_0_M00_AXI_AWBURST;
  wire [3:0]smartconnect_0_M00_AXI_AWCACHE;
  wire [7:0]smartconnect_0_M00_AXI_AWLEN;
  wire [0:0]smartconnect_0_M00_AXI_AWLOCK;
  wire [2:0]smartconnect_0_M00_AXI_AWPROT;
  wire [3:0]smartconnect_0_M00_AXI_AWQOS;
  wire smartconnect_0_M00_AXI_AWREADY;
  wire [2:0]smartconnect_0_M00_AXI_AWSIZE;
  wire smartconnect_0_M00_AXI_AWVALID;
  wire smartconnect_0_M00_AXI_BREADY;
  wire [1:0]smartconnect_0_M00_AXI_BRESP;
  wire smartconnect_0_M00_AXI_BVALID;
  wire [511:0]smartconnect_0_M00_AXI_RDATA;
  wire smartconnect_0_M00_AXI_RLAST;
  wire smartconnect_0_M00_AXI_RREADY;
  wire [1:0]smartconnect_0_M00_AXI_RRESP;
  wire smartconnect_0_M00_AXI_RVALID;
  wire [511:0]smartconnect_0_M00_AXI_WDATA;
  wire smartconnect_0_M00_AXI_WLAST;
  wire smartconnect_0_M00_AXI_WREADY;
  wire [63:0]smartconnect_0_M00_AXI_WSTRB;
  wire smartconnect_0_M00_AXI_WVALID;
  wire sys_rst_0;

  ddr_system_bd_ddr4_0_0 ddr4_0
       (.addn_ui_clkout1(addn_ui_clkout1_0),
        .c0_ddr4_act_n(C0_DDR4_0_act_n),
        .c0_ddr4_adr(C0_DDR4_0_adr),
        .c0_ddr4_aresetn(c0_ddr4_aresetn_0),
        .c0_ddr4_ba(C0_DDR4_0_ba),
        .c0_ddr4_bg(C0_DDR4_0_bg[0]),
        .c0_ddr4_ck_c(C0_DDR4_0_ck_c),
        .c0_ddr4_ck_t(C0_DDR4_0_ck_t),
        .c0_ddr4_cke(C0_DDR4_0_cke),
        .c0_ddr4_cs_n(C0_DDR4_0_cs_n),
        .c0_ddr4_dm_dbi_n(C0_DDR4_0_dm_n),
        .c0_ddr4_dq(C0_DDR4_0_dq),
        .c0_ddr4_dqs_c(C0_DDR4_0_dqs_c),
        .c0_ddr4_dqs_t(C0_DDR4_0_dqs_t),
        .c0_ddr4_odt(C0_DDR4_0_odt),
        .c0_ddr4_reset_n(C0_DDR4_0_reset_n),
        .c0_ddr4_s_axi_araddr(smartconnect_0_M00_AXI_ARADDR),
        .c0_ddr4_s_axi_arburst(smartconnect_0_M00_AXI_ARBURST),
        .c0_ddr4_s_axi_arcache(smartconnect_0_M00_AXI_ARCACHE),
        .c0_ddr4_s_axi_arid(1'b0),
        .c0_ddr4_s_axi_arlen(smartconnect_0_M00_AXI_ARLEN),
        .c0_ddr4_s_axi_arlock(smartconnect_0_M00_AXI_ARLOCK),
        .c0_ddr4_s_axi_arprot(smartconnect_0_M00_AXI_ARPROT),
        .c0_ddr4_s_axi_arqos(smartconnect_0_M00_AXI_ARQOS),
        .c0_ddr4_s_axi_arready(smartconnect_0_M00_AXI_ARREADY),
        .c0_ddr4_s_axi_arsize(smartconnect_0_M00_AXI_ARSIZE),
        .c0_ddr4_s_axi_arvalid(smartconnect_0_M00_AXI_ARVALID),
        .c0_ddr4_s_axi_awaddr(smartconnect_0_M00_AXI_AWADDR),
        .c0_ddr4_s_axi_awburst(smartconnect_0_M00_AXI_AWBURST),
        .c0_ddr4_s_axi_awcache(smartconnect_0_M00_AXI_AWCACHE),
        .c0_ddr4_s_axi_awid(1'b0),
        .c0_ddr4_s_axi_awlen(smartconnect_0_M00_AXI_AWLEN),
        .c0_ddr4_s_axi_awlock(smartconnect_0_M00_AXI_AWLOCK),
        .c0_ddr4_s_axi_awprot(smartconnect_0_M00_AXI_AWPROT),
        .c0_ddr4_s_axi_awqos(smartconnect_0_M00_AXI_AWQOS),
        .c0_ddr4_s_axi_awready(smartconnect_0_M00_AXI_AWREADY),
        .c0_ddr4_s_axi_awsize(smartconnect_0_M00_AXI_AWSIZE),
        .c0_ddr4_s_axi_awvalid(smartconnect_0_M00_AXI_AWVALID),
        .c0_ddr4_s_axi_bready(smartconnect_0_M00_AXI_BREADY),
        .c0_ddr4_s_axi_bresp(smartconnect_0_M00_AXI_BRESP),
        .c0_ddr4_s_axi_bvalid(smartconnect_0_M00_AXI_BVALID),
        .c0_ddr4_s_axi_rdata(smartconnect_0_M00_AXI_RDATA),
        .c0_ddr4_s_axi_rlast(smartconnect_0_M00_AXI_RLAST),
        .c0_ddr4_s_axi_rready(smartconnect_0_M00_AXI_RREADY),
        .c0_ddr4_s_axi_rresp(smartconnect_0_M00_AXI_RRESP),
        .c0_ddr4_s_axi_rvalid(smartconnect_0_M00_AXI_RVALID),
        .c0_ddr4_s_axi_wdata(smartconnect_0_M00_AXI_WDATA),
        .c0_ddr4_s_axi_wlast(smartconnect_0_M00_AXI_WLAST),
        .c0_ddr4_s_axi_wready(smartconnect_0_M00_AXI_WREADY),
        .c0_ddr4_s_axi_wstrb(smartconnect_0_M00_AXI_WSTRB),
        .c0_ddr4_s_axi_wvalid(smartconnect_0_M00_AXI_WVALID),
        .c0_ddr4_ui_clk(c0_ddr4_ui_clk_0),
        .c0_ddr4_ui_clk_sync_rst(c0_ddr4_ui_clk_sync_rst_0),
        .c0_init_calib_complete(c0_init_calib_complete_0),
        .c0_sys_clk_n(C0_SYS_CLK_0_clk_n),
        .c0_sys_clk_p(C0_SYS_CLK_0_clk_p),
        .dbg_bus(dbg_bus_0),
        .dbg_clk(dbg_clk_0),
        .sys_rst(sys_rst_0));
  ddr_system_bd_smartconnect_0_0 smartconnect_0
       (.M00_AXI_araddr(smartconnect_0_M00_AXI_ARADDR),
        .M00_AXI_arburst(smartconnect_0_M00_AXI_ARBURST),
        .M00_AXI_arcache(smartconnect_0_M00_AXI_ARCACHE),
        .M00_AXI_arlen(smartconnect_0_M00_AXI_ARLEN),
        .M00_AXI_arlock(smartconnect_0_M00_AXI_ARLOCK),
        .M00_AXI_arprot(smartconnect_0_M00_AXI_ARPROT),
        .M00_AXI_arqos(smartconnect_0_M00_AXI_ARQOS),
        .M00_AXI_arready(smartconnect_0_M00_AXI_ARREADY),
        .M00_AXI_arsize(smartconnect_0_M00_AXI_ARSIZE),
        .M00_AXI_arvalid(smartconnect_0_M00_AXI_ARVALID),
        .M00_AXI_awaddr(smartconnect_0_M00_AXI_AWADDR),
        .M00_AXI_awburst(smartconnect_0_M00_AXI_AWBURST),
        .M00_AXI_awcache(smartconnect_0_M00_AXI_AWCACHE),
        .M00_AXI_awlen(smartconnect_0_M00_AXI_AWLEN),
        .M00_AXI_awlock(smartconnect_0_M00_AXI_AWLOCK),
        .M00_AXI_awprot(smartconnect_0_M00_AXI_AWPROT),
        .M00_AXI_awqos(smartconnect_0_M00_AXI_AWQOS),
        .M00_AXI_awready(smartconnect_0_M00_AXI_AWREADY),
        .M00_AXI_awsize(smartconnect_0_M00_AXI_AWSIZE),
        .M00_AXI_awvalid(smartconnect_0_M00_AXI_AWVALID),
        .M00_AXI_bready(smartconnect_0_M00_AXI_BREADY),
        .M00_AXI_bresp(smartconnect_0_M00_AXI_BRESP),
        .M00_AXI_bvalid(smartconnect_0_M00_AXI_BVALID),
        .M00_AXI_rdata(smartconnect_0_M00_AXI_RDATA),
        .M00_AXI_rlast(smartconnect_0_M00_AXI_RLAST),
        .M00_AXI_rready(smartconnect_0_M00_AXI_RREADY),
        .M00_AXI_rresp(smartconnect_0_M00_AXI_RRESP),
        .M00_AXI_rvalid(smartconnect_0_M00_AXI_RVALID),
        .M00_AXI_wdata(smartconnect_0_M00_AXI_WDATA),
        .M00_AXI_wlast(smartconnect_0_M00_AXI_WLAST),
        .M00_AXI_wready(smartconnect_0_M00_AXI_WREADY),
        .M00_AXI_wstrb(smartconnect_0_M00_AXI_WSTRB),
        .M00_AXI_wvalid(smartconnect_0_M00_AXI_WVALID),
        .S00_AXI_araddr(S00_AXI_0_araddr),
        .S00_AXI_arburst(S00_AXI_0_arburst),
        .S00_AXI_arcache(S00_AXI_0_arcache),
        .S00_AXI_arid(S00_AXI_0_arid),
        .S00_AXI_arlen(S00_AXI_0_arlen),
        .S00_AXI_arlock(S00_AXI_0_arlock),
        .S00_AXI_arprot(S00_AXI_0_arprot),
        .S00_AXI_arqos(S00_AXI_0_arqos),
        .S00_AXI_arready(S00_AXI_0_arready),
        .S00_AXI_arsize(S00_AXI_0_arsize),
        .S00_AXI_arvalid(S00_AXI_0_arvalid),
        .S00_AXI_awaddr(S00_AXI_0_awaddr),
        .S00_AXI_awburst(S00_AXI_0_awburst),
        .S00_AXI_awcache(S00_AXI_0_awcache),
        .S00_AXI_awid(S00_AXI_0_awid),
        .S00_AXI_awlen(S00_AXI_0_awlen),
        .S00_AXI_awlock(S00_AXI_0_awlock),
        .S00_AXI_awprot(S00_AXI_0_awprot),
        .S00_AXI_awqos(S00_AXI_0_awqos),
        .S00_AXI_awready(S00_AXI_0_awready),
        .S00_AXI_awsize(S00_AXI_0_awsize),
        .S00_AXI_awvalid(S00_AXI_0_awvalid),
        .S00_AXI_bid(S00_AXI_0_bid),
        .S00_AXI_bready(S00_AXI_0_bready),
        .S00_AXI_bresp(S00_AXI_0_bresp),
        .S00_AXI_bvalid(S00_AXI_0_bvalid),
        .S00_AXI_rdata(S00_AXI_0_rdata),
        .S00_AXI_rid(S00_AXI_0_rid),
        .S00_AXI_rlast(S00_AXI_0_rlast),
        .S00_AXI_rready(S00_AXI_0_rready),
        .S00_AXI_rresp(S00_AXI_0_rresp),
        .S00_AXI_rvalid(S00_AXI_0_rvalid),
        .S00_AXI_wdata(S00_AXI_0_wdata),
        .S00_AXI_wlast(S00_AXI_0_wlast),
        .S00_AXI_wready(S00_AXI_0_wready),
        .S00_AXI_wstrb(S00_AXI_0_wstrb),
        .S00_AXI_wvalid(S00_AXI_0_wvalid),
        .aclk(c0_ddr4_ui_clk_0),
        .aresetn(c0_ddr4_aresetn_0));
endmodule

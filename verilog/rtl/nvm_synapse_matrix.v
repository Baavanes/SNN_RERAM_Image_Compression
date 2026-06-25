// nvm_synapse_matrix.v â 1 IP version


module nvm_synapse_matrix (
`ifdef USE_POWER_PINS
   inout         VDDC1,            // 0 V analog ground
   inout         VDDC2,            // 0 V analog ground
   inout         VDDA1,           // 1.8 V analog supply (mapped to vdda1)
   inout         VDDA2,           // 1.8 V analog supply (mapped to vdda1)
   inout         VSS,           // 1.8 V analog core digital supply (mapped to vccd1)
`endif
  input         wb_clk_i,
  input         wb_rst_i,
  input         user_clk,     // user clock
  input         user_rst,     // user reset
  input         wbs_stb_i,
  input         wbs_cyc_i,
  input         wbs_we_i,
  input  [3:0]  wbs_sel_i,
  input  [31:0] wbs_dat_i,
  input  [31:0] wbs_adr_i,
  output [31:0] wbs_dat_o,
  output reg    wbs_ack_o,
  input         ScanInCC,
  input         ScanInDL,
  input         ScanInDR,
  input         TM,
  output        ScanOutCC,
  input         Iref,
  input         Vcc_read,
  input         Vcomp,
  input         Bias_comp2,
  input         Vcc_wl_read,
  input         Vcc_wl_set,
  input         Vbias,
  input         Vcc_wl_reset,
  input         Vcc_set,
  input         dc_bias
);


  Neuromorphic_X1_wb X1_inst (
    `ifdef USE_POWER_PINS
      .VDDC1(VDDC1),
      .VDDC2(VDDC2),
      .VDDA1(VDDA1),
      .VDDA2(VDDA2),
      .VSS(VSS),
    `endif
    .user_clk (wb_clk_i),  .user_rst (wb_rst_i),
    .wb_clk_i (wb_clk_i),  .wb_rst_i (wb_rst_i),
    .wbs_stb_i(wbs_stb_i), .wbs_cyc_i(wbs_cyc_i),
    .wbs_we_i (wbs_we_i),  .wbs_sel_i(wbs_sel_i),
    .wbs_dat_i(wbs_dat_i),
    .wbs_adr_i(wbs_adr_i),
    .wbs_dat_o(wbs_dat_o), .wbs_ack_o(wbs_ack_o),
    .ScanInCC(ScanInCC), .ScanInDL(ScanInDL),
    .ScanInDR(ScanInDR), .TM(TM), .ScanOutCC(ScanOutCC),
    .Iref(Iref), .Vcc_read(Vcc_read), .Vcomp(Vcomp),
    .Bias_comp2(Bias_comp2), .Vcc_wl_read(Vcc_wl_read),
    .Vcc_wl_set(Vcc_wl_set), .Vbias(Vbias),
    .Vcc_wl_reset(Vcc_wl_reset), .Vcc_set(Vcc_set),
    .dc_bias(dc_bias)
  );


endmodule
// nvm_neuron_core_256x64.v — 1 IP version


module nvm_neuron_core_256x64 (
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
    output        wbs_ack_o,
    input         ScanInCC, input  ScanInDL, input  ScanInDR,
    input         TM,       output ScanOutCC,
    input         Iref,    input  Vcc_read,  input  Vcomp,
    input         Bias_comp2,               input  Vcc_wl_read,
    input         Vcc_wl_set,              input  Vbias,
    input         Vcc_wl_reset,            input  Vcc_set,
    input         dc_bias
);


  wire synapse_matrix_select;
  wire neuron_spike_out_select;
  wire picture_done;
  wire spike_latch;

  nvm_core_decoder core_decoder_inst (
    .addr                   (wbs_adr_i),
    .synapse_matrix_select  (synapse_matrix_select),
    .neuron_spike_out_select(neuron_spike_out_select),
    .picture_done           (picture_done),
    .spike_latch            (spike_latch)
  );


  wire phase_select = (wbs_adr_i[15:12] == 4'h4);
  reg [5:0] phase_reg;   // 0..63: which neuron to accumulate into

  always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i) phase_reg <= 6'd0;
    else if (wbs_cyc_i && wbs_stb_i && wbs_we_i && phase_select)
        phase_reg <= wbs_dat_i[5:0];
  end


  reg phase_ack;
  always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i) phase_ack <= 1'b0;
    else          phase_ack <= wbs_cyc_i & wbs_stb_i & wbs_we_i & phase_select;
  end


  wire [31:0] slave_dat_o [1:0];
  wire  [1:0] slave_ack_o;
  wire [63:0] spike_o;


  wire connection = slave_dat_o[0][0];


  wire matrix_write = wbs_cyc_i & wbs_stb_i & wbs_we_i & synapse_matrix_select;
  wire matrix_read  = wbs_cyc_i & wbs_stb_i & ~wbs_we_i & synapse_matrix_select;
  wire read_command = matrix_write & (wbs_dat_i[31:30] == 2'b01);
  wire signed [15:0] command_stimuli =
    wbs_dat_i[28] ? -$signed(wbs_dat_i[15:0]) : $signed(wbs_dat_i[15:0]);

  reg signed [15:0] stimuli_r;
  reg [5:0] target_neuron_r;
  reg read_pending_r;
  reg neuron_enable_r;

  wire read_result_ack = read_pending_r & matrix_read & slave_ack_o[0];

  always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i) begin
      stimuli_r       <= 16'sd0;
      target_neuron_r <= 6'd0;
      read_pending_r  <= 1'b0;
      neuron_enable_r <= 1'b0;
    end else begin
      neuron_enable_r <= read_result_ack;

      if (read_command) begin
        stimuli_r       <= command_stimuli;
        target_neuron_r <= phase_reg;
        read_pending_r  <= 1'b1;
      end else if (read_result_ack) begin
        read_pending_r  <= 1'b0;
      end
    end
  end


  nvm_synapse_matrix synapse_matrix_inst (
`ifdef USE_POWER_PINS
    .VDDC1(VDDC1),
      .VDDC2(VDDC2),
      .VDDA1(VDDA1),
      .VDDA2(VDDA2),
      .VSS(VSS),
`endif
    .wb_clk_i (wb_clk_i),  .wb_rst_i (wb_rst_i),
    .user_clk (user_clk),  .user_rst (user_rst),
    .wbs_stb_i(wbs_stb_i & synapse_matrix_select),
    .wbs_cyc_i(wbs_cyc_i & synapse_matrix_select),
    .wbs_we_i (wbs_we_i  & synapse_matrix_select),
    .wbs_sel_i(wbs_sel_i), .wbs_dat_i(wbs_dat_i),
    .wbs_adr_i(wbs_adr_i), .wbs_dat_o(slave_dat_o[0]),
    .wbs_ack_o(slave_ack_o[0]),
    .ScanInCC(ScanInCC), .ScanInDL(ScanInDL), .ScanInDR(ScanInDR),
    .TM(TM), .ScanOutCC(ScanOutCC),
    .Iref(Iref), .Vcc_read(Vcc_read), .Vcomp(Vcomp),
    .Bias_comp2(Bias_comp2), .Vcc_wl_read(Vcc_wl_read),
    .Vcc_wl_set(Vcc_wl_set), .Vbias(Vbias),
    .Vcc_wl_reset(Vcc_wl_reset), .Vcc_set(Vcc_set),
    .dc_bias(dc_bias)
  );


  nvm_neuron_block neuron_block_inst (
    .clk          (wb_clk_i),
    .rst          (wb_rst_i),
    .stimuli      (stimuli_r),
    .connection   (connection),
    .target_neuron(target_neuron_r),  // phase captured with the X1 read command
    .picture_done (wbs_cyc_i & wbs_stb_i & wbs_we_i & picture_done),
    .enable       (neuron_enable_r),  // one cycle after X1 read data ACK, so DO is valid
    .spike_o      (spike_o)
  );


  wire [31:0] spike_write_data =
    wbs_adr_i[2] ? {spike_o[63:48], spike_o[47:32]}
                 : {spike_o[31:16], spike_o[15:0]};

  nvm_neuron_spike_out spike_out_inst (
    .wb_clk_i (wb_clk_i), .wb_rst_i (wb_rst_i),
    .wbs_cyc_i(wbs_cyc_i & (neuron_spike_out_select | spike_latch)),
    .wbs_stb_i(wbs_stb_i & (neuron_spike_out_select | spike_latch)),
    .wbs_we_i (wbs_we_i  & (neuron_spike_out_select | spike_latch)),
    .wbs_sel_i(wbs_sel_i), .wbs_adr_i(wbs_adr_i),
    .wbs_dat_i(spike_write_data),
    .wbs_ack_o(slave_ack_o[1]), .wbs_dat_o(slave_dat_o[1]),
    .latch_enable(wbs_cyc_i & wbs_stb_i & wbs_we_i & spike_latch)
  );


  assign wbs_dat_o = synapse_matrix_select  ? slave_dat_o[0] :
                     neuron_spike_out_select ? slave_dat_o[1] :
                     32'b0;

  reg picture_done_ack;
  always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i) picture_done_ack <= 1'b0;
    else          picture_done_ack <= wbs_cyc_i & wbs_stb_i & wbs_we_i & picture_done;
  end

  assign wbs_ack_o = |slave_ack_o | picture_done_ack | phase_ack;

endmodule
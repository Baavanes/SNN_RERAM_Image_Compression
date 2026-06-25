`default_nettype none
module user_project_wrapper #(
    parameter BITS = 32
) (
`ifdef USE_POWER_PINS
    inout vdda1, inout vdda2,
    inout vssa1, inout vssa2,
    inout vccd1, inout vccd2,
    inout vssd1, inout vssd2,
`endif

    input         wb_clk_i,
    input         wb_rst_i,
    input         wbs_stb_i,
    input         wbs_cyc_i,
    input         wbs_we_i,
    input  [3:0]  wbs_sel_i,
    input  [31:0] wbs_dat_i,
    input  [31:0] wbs_adr_i,
    output        wbs_ack_o,
    output [31:0] wbs_dat_o,

    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    inout  [`MPRJ_IO_PADS-10:0] analog_io,

    input   user_clock2,
    output [2:0] user_irq
);

  wire scan_in_cc;
  wire scan_in_dl;
  wire scan_in_dr;
  wire tm;
  wire scan_out_cc;
  wire [31:0] img_debug_status;
  wire [2:0] img_event_irq;
  reg [`MPRJ_IO_PADS-1:0] io_out_r;
  reg [`MPRJ_IO_PADS-1:0] io_oeb_r;

  assign scan_in_dr = io_in[21];
  assign scan_in_dl = io_in[22];
  assign scan_in_cc = io_in[35];
  assign tm = io_in[36];

  assign io_out = io_out_r;
  assign io_oeb = io_oeb_r;

  always @(*) begin
    io_out_r = {`MPRJ_IO_PADS{1'b0}};
    io_oeb_r = {`MPRJ_IO_PADS{1'b1}};

    io_oeb_r[21] = 1'b0;
    io_out_r[22] = 1'b1;
    io_oeb_r[22] = 1'b0;
    io_out_r[23] = scan_out_cc;
    io_oeb_r[23] = 1'b0;
    io_oeb_r[35] = 1'b0;
    io_out_r[36] = 1'b1;
    io_oeb_r[36] = 1'b0;
  end

  assign la_data_out = {96'd0, img_debug_status};
  assign user_irq = img_event_irq;

  image_compression_storage img_comp_inst (
`ifdef USE_POWER_PINS
    .VDDC1 (vccd1),
    .VDDC2 (vccd2),
    .VDDA1 (vdda1),
    .VDDA2 (vdda2),
    .VSS   (vssd1),
`endif
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .user_clk(wb_clk_i),
    .user_rst(wb_rst_i),
    .wbs_stb_i(wbs_stb_i),
    .wbs_cyc_i(wbs_cyc_i),
    .wbs_we_i(wbs_we_i),
    .wbs_sel_i(wbs_sel_i),
    .wbs_dat_i(wbs_dat_i),
    .wbs_adr_i(wbs_adr_i),
    .wbs_dat_o(wbs_dat_o),
    .wbs_ack_o(wbs_ack_o),
    .ScanInCC(scan_in_cc),
    .ScanInDL(scan_in_dl),
    .ScanInDR(scan_in_dr),
    .TM(tm),
    .ScanOutCC(scan_out_cc),
    .Iref(analog_io[27]),
    .Vcc_read(analog_io[26]),
    .Vcomp(analog_io[25]),
    .Bias_comp2(analog_io[24]),
    .Vcc_wl_read(analog_io[19]),
    .Vcc_wl_set(analog_io[23]),
    .Vbias(analog_io[22]),
    .Vcc_wl_reset(analog_io[21]),
    .Vcc_set(analog_io[20]),
    .dc_bias(analog_io[18]),
    .debug_status(img_debug_status),
    .image_irq(img_event_irq)
  );

endmodule
`default_nettype wire

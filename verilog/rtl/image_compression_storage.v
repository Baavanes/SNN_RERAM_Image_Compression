`default_nettype none

module image_compression_storage (
`ifdef USE_POWER_PINS
    inout         VDDC1,
    inout         VDDC2,
    inout         VDDA1,
    inout         VDDA2,
    inout         VSS,
`endif
    input         wb_clk_i,
    input         wb_rst_i,
    input         user_clk,
    input         user_rst,

    input         wbs_stb_i,
    input         wbs_cyc_i,
    input         wbs_we_i,
    input  [3:0]  wbs_sel_i,
    input  [31:0] wbs_dat_i,
    input  [31:0] wbs_adr_i,
    output reg [31:0] wbs_dat_o,
    output reg        wbs_ack_o,

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
    input         dc_bias,

    output [31:0] debug_status,
    output [2:0]  image_irq
);

  localparam [31:0] X1_ADDR = 32'h3000_0004;

  localparam [3:0] OP_LOAD_PIXEL     = 4'h2;
  localparam [3:0] OP_COMPRESS_BLOCK = 4'h3;
  localparam [3:0] OP_READ_BIT       = 4'h4;
  localparam [3:0] OP_CLEAR_BLOCK    = 4'h5;
  localparam [3:0] OP_READ_MASK      = 4'h6;

  localparam [4:0] ST_CFG_WRITE       = 5'd0;
  localparam [4:0] ST_IDLE            = 5'd1;
  localparam [4:0] ST_COMPRESS_NEXT   = 5'd2;
  localparam [4:0] ST_COMPRESS_WRITE  = 5'd3;
  localparam [4:0] ST_READ_CMD        = 5'd4;
  localparam [4:0] ST_READ_POP        = 5'd5;
  localparam [4:0] ST_CLEAR_NEXT      = 5'd6;
  localparam [4:0] ST_CLEAR_WRITE     = 5'd7;
  localparam [4:0] ST_MASK_NEXT       = 5'd8;
  localparam [4:0] ST_MASK_CMD        = 5'd9;
  localparam [4:0] ST_MASK_POP        = 5'd10;
  localparam [4:0] ST_DONE            = 5'd11;

  reg [4:0] state;
  reg [4:0] idx_r;
  reg [2:0] cfg_index;

  reg [3:0] cmd_op;
  reg [3:0] cmd_block;
  reg [7:0] cmd_pixel;
  reg [7:0] cmd_threshold;
  reg [3:0] cmd_index;

  reg [7:0]  pixel_buf [0:15];
  reg [15:0] valid_mask_r;
  reg [15:0] compressed_mask_r;
  reg [15:0] mask_read_r;
  reg [7:0]  count_r;
  reg [4:0]  active_col;

  reg [31:0] result_r;
  reg [31:0] last_command_r;
  reg        done_r;
  reg        configured_r;
  reg        error_r;
  reg        compressed_ready_r;
  reg        host_cmd_valid;
  reg        host_cmd_reject;

  reg        x1_cyc_r;
  reg        x1_stb_r;
  reg        x1_we_r;
  reg [31:0] x1_dat_i_r;
  wire [31:0] x1_dat_o;
  wire        x1_ack;

  wire host_sel = wbs_cyc_i && wbs_stb_i && (wbs_adr_i[31:16] == 16'h3000);
  wire [1:0] host_word = wbs_adr_i[3:2];
  wire busy = (state != ST_IDLE);

  integer i;

  assign debug_status = {
      8'h49,
      2'b00,
      state,
      compressed_ready_r,
      configured_r,
      error_r,
      done_r,
      busy,
      count_r,
      cmd_block
  };

  assign image_irq = {error_r, done_r, compressed_ready_r};

  function [31:0] x1_program_cmd;
    input [4:0] row;
    input [4:0] col;
    begin
      x1_program_cmd = 32'hC000_00FF | ({27'd0, row} << 25) | ({27'd0, col} << 20);
    end
  endfunction

  function [31:0] x1_reset_cmd;
    input [4:0] row;
    input [4:0] col;
    begin
      x1_reset_cmd = ({27'd0, row} << 25) | ({27'd0, col} << 20);
    end
  endfunction

  function [31:0] x1_read_cmd;
    input [4:0] row;
    input [4:0] col;
    begin
      x1_read_cmd = 32'h4000_0000 | ({27'd0, row} << 25) | ({27'd0, col} << 20);
    end
  endfunction

  function [31:0] x1_config_word;
    input [2:0] index;
    begin
      case (index)
        3'd0: x1_config_word = 32'hA203_C40F;
        3'd1: x1_config_word = 32'h0F03_0D43;
        default: x1_config_word = 32'h4200_0C03;
      endcase
    end
  endfunction

  always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i) begin
      wbs_ack_o <= 1'b0;
      wbs_dat_o <= 32'd0;
      host_cmd_valid <= 1'b0;
      host_cmd_reject <= 1'b0;
      last_command_r <= 32'd0;
    end else begin
      wbs_ack_o <= 1'b0;
      host_cmd_valid <= 1'b0;
      host_cmd_reject <= 1'b0;
      if (host_sel && !wbs_ack_o) begin
        wbs_ack_o <= 1'b1;
        if (wbs_we_i && host_word == 2'd1) begin
          if (!busy && configured_r) begin
            cmd_op <= wbs_dat_i[31:28];
            cmd_block <= wbs_dat_i[27:24];
            cmd_pixel <= wbs_dat_i[23:16];
            cmd_threshold <= wbs_dat_i[15:8];
            cmd_index <= wbs_dat_i[3:0];
            last_command_r <= wbs_dat_i;
            host_cmd_valid <= 1'b1;
          end else begin
            host_cmd_reject <= 1'b1;
          end
        end else if (!wbs_we_i) begin
          case (host_word)
            2'd0: wbs_dat_o <= debug_status;
            2'd1: wbs_dat_o <= last_command_r;
            2'd2: wbs_dat_o <= result_r;
            default: wbs_dat_o <= {16'h494D, compressed_mask_r};
          endcase
        end
      end
    end
  end

  always @(posedge wb_clk_i or posedge wb_rst_i) begin
    if (wb_rst_i) begin
      state <= ST_CFG_WRITE;
      idx_r <= 5'd0;
      cfg_index <= 3'd0;
      result_r <= 32'd0;
      done_r <= 1'b0;
      configured_r <= 1'b0;
      error_r <= 1'b0;
      compressed_ready_r <= 1'b0;
      valid_mask_r <= 16'd0;
      compressed_mask_r <= 16'd0;
      mask_read_r <= 16'd0;
      count_r <= 8'd0;
      active_col <= 5'd0;
      x1_cyc_r <= 1'b0;
      x1_stb_r <= 1'b0;
      x1_we_r <= 1'b1;
      x1_dat_i_r <= 32'd0;
      for (i = 0; i < 16; i = i + 1)
        pixel_buf[i] <= 8'd0;
    end else begin
      if (host_cmd_reject) begin
        error_r <= 1'b1;
        done_r <= 1'b1;
        result_r <= 32'h8000_00EF;
      end

      case (state)
        ST_CFG_WRITE: begin
          x1_cyc_r <= 1'b1;
          x1_stb_r <= 1'b1;
          x1_we_r <= 1'b1;
          x1_dat_i_r <= x1_config_word(cfg_index);
          if (x1_ack) begin
            x1_cyc_r <= 1'b0;
            x1_stb_r <= 1'b0;
            if (cfg_index == 3'd2) begin
              configured_r <= 1'b1;
              state <= ST_IDLE;
            end else begin
              cfg_index <= cfg_index + 1'b1;
            end
          end
        end

        ST_IDLE: begin
          x1_cyc_r <= 1'b0;
          x1_stb_r <= 1'b0;
          x1_we_r <= 1'b1;
          if (host_cmd_valid) begin
            done_r <= 1'b0;
            error_r <= 1'b0;
            case (cmd_op)
              OP_LOAD_PIXEL: begin
                pixel_buf[cmd_index] <= cmd_pixel;
                valid_mask_r[cmd_index] <= 1'b1;
                compressed_ready_r <= 1'b0;
                result_r <= {1'b1, 3'b000, cmd_block, cmd_index, cmd_pixel, 12'd0};
                state <= ST_DONE;
              end
              OP_COMPRESS_BLOCK: begin
                idx_r <= 5'd0;
                count_r <= 8'd0;
                compressed_mask_r <= 16'd0;
                compressed_ready_r <= 1'b0;
                state <= ST_COMPRESS_NEXT;
              end
              OP_READ_BIT: begin
                active_col <= {1'b0, cmd_index};
                state <= ST_READ_CMD;
              end
              OP_CLEAR_BLOCK: begin
                idx_r <= 5'd0;
                count_r <= 8'd0;
                valid_mask_r <= 16'd0;
                compressed_mask_r <= 16'd0;
                mask_read_r <= 16'd0;
                compressed_ready_r <= 1'b0;
                state <= ST_CLEAR_NEXT;
              end
              OP_READ_MASK: begin
                idx_r <= 5'd0;
                count_r <= 8'd0;
                mask_read_r <= 16'd0;
                state <= ST_MASK_NEXT;
              end
              default: begin
                result_r <= 32'h8000_00EE;
                state <= ST_DONE;
              end
            endcase
          end
        end

        ST_COMPRESS_NEXT: begin
          if (idx_r > 5'd15) begin
            result_r <= {1'b1, 3'b000, cmd_block, count_r, compressed_mask_r};
            compressed_ready_r <= 1'b1;
            state <= ST_DONE;
          end else begin
            active_col <= {1'b0, idx_r[3:0]};
            if (valid_mask_r[idx_r[3:0]] && (pixel_buf[idx_r[3:0]] >= cmd_threshold)) begin
              x1_cyc_r <= 1'b1;
              x1_stb_r <= 1'b1;
              x1_we_r <= 1'b1;
              x1_dat_i_r <= x1_program_cmd({1'b0, cmd_block}, {1'b0, idx_r[3:0]});
              compressed_mask_r[idx_r[3:0]] <= 1'b1;
              count_r <= count_r + 1'b1;
              state <= ST_COMPRESS_WRITE;
            end else begin
              compressed_mask_r[idx_r[3:0]] <= 1'b0;
              idx_r <= idx_r + 1'b1;
            end
          end
        end

        ST_COMPRESS_WRITE: begin
          if (x1_ack) begin
            x1_cyc_r <= 1'b0;
            x1_stb_r <= 1'b0;
            idx_r <= idx_r + 1'b1;
            state <= ST_COMPRESS_NEXT;
          end
        end

        ST_READ_CMD: begin
          x1_cyc_r <= 1'b1;
          x1_stb_r <= 1'b1;
          x1_we_r <= 1'b1;
          x1_dat_i_r <= x1_read_cmd({1'b0, cmd_block}, active_col);
          if (x1_ack) begin
            x1_cyc_r <= 1'b0;
            x1_stb_r <= 1'b0;
            state <= ST_READ_POP;
          end
        end

        ST_READ_POP: begin
          x1_cyc_r <= 1'b1;
          x1_stb_r <= 1'b1;
          x1_we_r <= 1'b0;
          x1_dat_i_r <= 32'd0;
          if (x1_ack) begin
            x1_cyc_r <= 1'b0;
            x1_stb_r <= 1'b0;
            result_r <= {1'b1, 3'b000, cmd_block, 4'd0, cmd_index, 15'd0, x1_dat_o[0]};
            state <= ST_DONE;
          end
        end

        ST_CLEAR_NEXT: begin
          if (idx_r > 5'd15) begin
            result_r <= {1'b1, 3'b000, cmd_block, 24'd0};
            state <= ST_DONE;
          end else begin
            active_col <= {1'b0, idx_r[3:0]};
            x1_cyc_r <= 1'b1;
            x1_stb_r <= 1'b1;
            x1_we_r <= 1'b1;
            x1_dat_i_r <= x1_reset_cmd({1'b0, cmd_block}, {1'b0, idx_r[3:0]});
            state <= ST_CLEAR_WRITE;
          end
        end

        ST_CLEAR_WRITE: begin
          if (x1_ack) begin
            x1_cyc_r <= 1'b0;
            x1_stb_r <= 1'b0;
            idx_r <= idx_r + 1'b1;
            state <= ST_CLEAR_NEXT;
          end
        end

        ST_MASK_NEXT: begin
          if (idx_r > 5'd15) begin
            compressed_mask_r <= mask_read_r;
            compressed_ready_r <= 1'b1;
            result_r <= {1'b1, 3'b000, cmd_block, count_r, mask_read_r};
            state <= ST_DONE;
          end else begin
            active_col <= {1'b0, idx_r[3:0]};
            x1_cyc_r <= 1'b1;
            x1_stb_r <= 1'b1;
            x1_we_r <= 1'b1;
            x1_dat_i_r <= x1_read_cmd({1'b0, cmd_block}, {1'b0, idx_r[3:0]});
            state <= ST_MASK_CMD;
          end
        end

        ST_MASK_CMD: begin
          if (x1_ack) begin
            x1_cyc_r <= 1'b0;
            x1_stb_r <= 1'b0;
            state <= ST_MASK_POP;
          end
        end

        ST_MASK_POP: begin
          x1_cyc_r <= 1'b1;
          x1_stb_r <= 1'b1;
          x1_we_r <= 1'b0;
          x1_dat_i_r <= 32'd0;
          if (x1_ack) begin
            x1_cyc_r <= 1'b0;
            x1_stb_r <= 1'b0;
            if (x1_dat_o[0]) begin
              mask_read_r[idx_r[3:0]] <= 1'b1;
              count_r <= count_r + 1'b1;
            end else begin
              mask_read_r[idx_r[3:0]] <= 1'b0;
            end
            idx_r <= idx_r + 1'b1;
            state <= ST_MASK_NEXT;
          end
        end

        ST_DONE: begin
          done_r <= 1'b1;
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  nvm_neuron_core_256x64 x1_core (
`ifdef USE_POWER_PINS
    .VDDC1(VDDC1),
    .VDDC2(VDDC2),
    .VDDA1(VDDA1),
    .VDDA2(VDDA2),
    .VSS(VSS),
`endif
    .user_clk(user_clk),
    .user_rst(user_rst),
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wbs_stb_i(x1_stb_r),
    .wbs_cyc_i(x1_cyc_r),
    .wbs_we_i(x1_we_r),
    .wbs_sel_i(4'hF),
    .wbs_dat_i(x1_dat_i_r),
    .wbs_adr_i(X1_ADDR),
    .wbs_dat_o(x1_dat_o),
    .wbs_ack_o(x1_ack),
    .ScanInCC(ScanInCC),
    .ScanInDL(ScanInDL),
    .ScanInDR(ScanInDR),
    .TM(TM),
    .ScanOutCC(ScanOutCC),
    .Iref(Iref),
    .Vcc_read(Vcc_read),
    .Vcomp(Vcomp),
    .Bias_comp2(Bias_comp2),
    .Vcc_wl_read(Vcc_wl_read),
    .Vcc_wl_set(Vcc_wl_set),
    .Vbias(Vbias),
    .Vcc_wl_reset(Vcc_wl_reset),
    .Vcc_set(Vcc_set),
    .dc_bias(dc_bias)
  );

endmodule

`default_nettype wire

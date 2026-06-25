module nvm_core_decoder (
  input      [31:0] addr,
  output reg        synapse_matrix_select,
  output reg        neuron_spike_out_select,
  output reg        picture_done,
  output reg        spike_latch          // NEW: addr[15:12]==3 latches spikes, no reset
  );

  always @(*) begin
    synapse_matrix_select  = 0;
    neuron_spike_out_select = 0;
    picture_done           = 0;
    spike_latch            = 0;

    case (addr[15:12])
      0: synapse_matrix_select  = 1;   // 0x3000_0xxx  inference reads / weight writes
      1: neuron_spike_out_select = 1;   // 0x3000_1xxx  spike SRAM reads
      2: picture_done            = 1;   // 0x3000_2xxx  RESET neurons only
      3: spike_latch             = 1;   // 0x3000_3xxx  latch spike_o → sram (no reset)
      default:;
    endcase
  end
endmodule

// nvm_neuron_block.v — 1 IP version


module nvm_neuron_block (
    input  wire        clk,
    input  wire        rst,
    input  wire signed [15:0] stimuli,    // signed: +stim or -stim applied in core
    input  wire        connection,         // 1 bit from single X1 macro
    input  wire [5:0]  target_neuron,      // which neuron to accumulate into (0..63)
    input  wire        picture_done,       // reset all potentials
    input  wire        enable,             // accumulate on this cycle
    output wire [63:0] spike_o
);
    parameter NUM_NEURONS = 64;

    reg signed [15:0] potential [0:NUM_NEURONS-1];
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < NUM_NEURONS; i = i + 1)
                potential[i] <= 16'd0;
        end
        else if (picture_done) begin
            for (i = 0; i < NUM_NEURONS; i = i + 1)
                potential[i] <= 16'd0;
        end
        else if (enable && connection) begin
            // Accumulate stimuli into the single target neuron for this phase
            potential[target_neuron] <= potential[target_neuron] + stimuli;
        end
    end

    // Spike = 1 when potential >= 0 (MSB = sign bit = 0)
    genvar n;
    generate
        for (n = 0; n < NUM_NEURONS; n = n + 1) begin : spike_gen
            assign spike_o[n] = ~potential[n][15];
        end
    endgenerate

endmodule

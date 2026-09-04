`timescale 1 ns / 1 ps

module Fixed_Point_Multiplier #(
    parameter DATA_DWIDTH = 16
)(
    input  wire                                  CLK,
    input  wire                                  RST,
    input  wire                                  valid_i,
    input  wire signed [DATA_DWIDTH-1:0]         operand_a_i,
    input  wire signed [DATA_DWIDTH-1:0]         operand_b_i,
    output reg  signed [(2*DATA_DWIDTH)-1:0]     product_o,
    output reg                                   valid_o
);

    //-------------------------------------//
    //      Two-Stage Multiplier Pipe      //
    //-------------------------------------//
    reg signed [DATA_DWIDTH-1:0] operand_a_r;
    reg signed [DATA_DWIDTH-1:0] operand_b_r;
    reg                           valid_stage1_r;

    // Vivado hint only. Synopsys Design Compiler ignores this attribute and
    // maps the portable multiplication to the target technology library.
    (* use_dsp = "yes" *)
    wire signed [(2*DATA_DWIDTH)-1:0] product_w;

    assign product_w = $signed(operand_a_r) * $signed(operand_b_r);

    // The datapath registers intentionally have no reset. Their contents are
    // ignored until valid_o is asserted; this also preserves DSP inference.
    always @(posedge CLK) begin
        operand_a_r <= operand_a_i;
        operand_b_r <= operand_b_i;
        product_o   <= product_w;
    end

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            valid_stage1_r <= 1'b0;
            valid_o        <= 1'b0;
        end
        else begin
            valid_stage1_r <= valid_i;
            valid_o        <= valid_stage1_r;
        end
    end

endmodule

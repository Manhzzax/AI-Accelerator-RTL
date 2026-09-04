`timescale 1 ns / 1 ps

module Fixed_Point_Quantizer #(
    parameter DATA_DWIDTH  = 16,
    parameter ACC_DWIDTH   = 48,
    parameter SHIFT_DWIDTH = 6
)(
    input  wire                              CLK,
    input  wire                              RST,
    input  wire                              valid_i,
    input  wire signed [ACC_DWIDTH-1:0]      accumulator_i,
    input  wire [SHIFT_DWIDTH-1:0]           output_shift_i,
    output reg  signed [DATA_DWIDTH-1:0]     quantized_o,
    output reg                               valid_o
);

    //-------------------------------------//
    //              Functions              //
    //-------------------------------------//
    function signed [ACC_DWIDTH-1:0] round_shift_signed;
        input signed [ACC_DWIDTH-1:0] value_i;
        input        [SHIFT_DWIDTH-1:0] shift_i;
        reg   signed [ACC_DWIDTH:0] value_ext_r;
        reg   signed [ACC_DWIDTH:0] round_const_r;
        reg   signed [ACC_DWIDTH:0] round_adjust_r;
        reg   signed [ACC_DWIDTH:0] rounded_r;
        begin
            value_ext_r    = {value_i[ACC_DWIDTH-1], value_i};
            round_const_r  = {(ACC_DWIDTH+1){1'b0}};
            round_adjust_r = {(ACC_DWIDTH+1){1'b0}};
            rounded_r      = value_ext_r;

            if (shift_i >= ACC_DWIDTH) begin
                rounded_r = {(ACC_DWIDTH+1){1'b0}};
            end
            else if (shift_i != 0) begin
                round_const_r = {{ACC_DWIDTH{1'b0}}, 1'b1} <<
                                (shift_i - 1'b1);

                // Exact symmetric round-to-nearest, with exact half cases
                // rounded away from zero. For negative values this cheaper
                // offset is equivalent to rounding the magnitude and restoring
                // the sign, but avoids two wide two's-complement operations.
                if (value_ext_r[ACC_DWIDTH]) begin
                    round_adjust_r = round_const_r - 1'b1;
                end
                else begin
                    round_adjust_r = round_const_r;
                end

                rounded_r = (value_ext_r + round_adjust_r) >>> shift_i;
            end

            round_shift_signed = rounded_r[ACC_DWIDTH-1:0];
        end
    endfunction

    function [DATA_DWIDTH-1:0] saturate_data;
        input signed [ACC_DWIDTH-1:0] value_i;
        reg   signed [ACC_DWIDTH-1:0] max_value_r;
        reg   signed [ACC_DWIDTH-1:0] min_value_r;
        begin
            max_value_r = {{(ACC_DWIDTH-DATA_DWIDTH){1'b0}},
                           1'b0,
                           {(DATA_DWIDTH-1){1'b1}}};
            min_value_r = {{(ACC_DWIDTH-DATA_DWIDTH){1'b1}},
                           1'b1,
                           {(DATA_DWIDTH-1){1'b0}}};

            if (value_i > max_value_r) begin
                saturate_data = {1'b0, {(DATA_DWIDTH-1){1'b1}}};
            end
            else if (value_i < min_value_r) begin
                saturate_data = {1'b1, {(DATA_DWIDTH-1){1'b0}}};
            end
            else begin
                saturate_data = value_i[DATA_DWIDTH-1:0];
            end
        end
    endfunction

    //-------------------------------------//
    //       Two-Stage Quantizer Pipe      //
    //-------------------------------------//
    wire signed [ACC_DWIDTH-1:0] shifted_w;
    reg  signed [ACC_DWIDTH-1:0] shifted_r;
    reg                           valid_stage1_r;

    assign shifted_w = round_shift_signed(accumulator_i, output_shift_i);

    // Stage 1: rounded layer-wise arithmetic shift.
    // Stage 2: signed 16-bit saturation and output register.
    always @(posedge CLK) begin
        shifted_r   <= shifted_w;
        quantized_o <= saturate_data(shifted_r);
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

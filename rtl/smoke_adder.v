`timescale 1ns / 1ps

// Simple 16-bit adder for environment smoke testing
module smoke_adder (
    input  wire [15:0] a_i,
    input  wire [15:0] b_i,
    output wire [15:0] sum_o
);

    assign sum_o = a_i + b_i;

endmodule

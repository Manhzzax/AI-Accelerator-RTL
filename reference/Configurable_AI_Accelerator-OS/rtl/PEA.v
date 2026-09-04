`timescale 1 ns / 1 ps

module PEA #(
    parameter DATA_DWIDTH     = 16,
    parameter ACC_DWIDTH      = 48,
    parameter SHIFT_DWIDTH    = 6,
    parameter COL_PE_NUM      = 16,
    parameter ROW_PE_NUM      = 4,
    parameter FM_BANK_NUM     = 16,
    parameter BANK_SEL_DWIDTH = 4
)(
    input  wire                                       CLK,
    input  wire                                       RST,

    //================================//
    //             Control            //
    //================================//
    input  wire                                       first_ifmap_i,
    input  wire                                       last_ifmap_i,
    input  wire                                       execute_i,
    input  wire [COL_PE_NUM-1:0]                      lane_enable_i,
    input  wire [ROW_PE_NUM-1:0]                      row_enable_i,
    input  wire [SHIFT_DWIDTH-1:0]                    output_shift_i,
    input  wire [BANK_SEL_DWIDTH-1:0]                 ofmap_bank_offset_i,

    //================================//
    //       Parallel IFMAP Vector    //
    //================================//
    input  wire signed [(COL_PE_NUM*DATA_DWIDTH)-1:0] ifmap_vector_i,

    //================================//
    //         Row Weights/Biases     //
    //================================//
    input  wire signed [DATA_DWIDTH-1:0]              row0_mem_weight_i,
    input  wire                                       row0_mem_weight_valid_i,
    input  wire signed [DATA_DWIDTH-1:0]              row1_mem_weight_i,
    input  wire                                       row1_mem_weight_valid_i,
    input  wire signed [DATA_DWIDTH-1:0]              row2_mem_weight_i,
    input  wire                                       row2_mem_weight_valid_i,
    input  wire signed [DATA_DWIDTH-1:0]              row3_mem_weight_i,
    input  wire                                       row3_mem_weight_valid_i,

    input  wire signed [DATA_DWIDTH-1:0]              row0_mem_bias_i,
    input  wire                                       row0_mem_bias_valid_i,
    input  wire signed [DATA_DWIDTH-1:0]              row1_mem_bias_i,
    input  wire                                       row1_mem_bias_valid_i,
    input  wire signed [DATA_DWIDTH-1:0]              row2_mem_bias_i,
    input  wire                                       row2_mem_bias_valid_i,
    input  wire signed [DATA_DWIDTH-1:0]              row3_mem_bias_i,
    input  wire                                       row3_mem_bias_valid_i,

    //================================//
    //          16-Bank OFMAP         //
    //================================//
    output reg  signed [(FM_BANK_NUM*DATA_DWIDTH)-1:0] bank_mem_ofmap_o,
    output reg  [FM_BANK_NUM-1:0]                      bank_mem_ofmap_valid_o
);

    localparam integer PE_NUM = COL_PE_NUM * ROW_PE_NUM;

    //-------------------------------------//
    //              Function               //
    //-------------------------------------//
    function [1:0] find_last_row;
        input [ROW_PE_NUM-1:0] row_mask_i;
        integer row_idx_r;
        begin
            find_last_row = 2'd0;
            for (row_idx_r = 0; row_idx_r < ROW_PE_NUM; row_idx_r = row_idx_r + 1) begin
                if (row_mask_i[row_idx_r]) begin
                    find_last_row = row_idx_r[1:0];
                end
            end
        end
    endfunction

    //-------------------------------------//
    //          Wire Declarations          //
    //-------------------------------------//
    wire signed [ACC_DWIDTH-1:0]           acc_ofmap_w [0:PE_NUM-1];
    wire                                    acc_ofmap_valid_w [0:PE_NUM-1];
    wire signed [DATA_DWIDTH-1:0]          south_ifmap_w [0:PE_NUM-1];
    wire                                    south_ifmap_valid_w [0:PE_NUM-1];
    wire signed [DATA_DWIDTH-1:0]          west_ifmap_w [0:PE_NUM-1];
    wire                                    west_ifmap_valid_w [0:PE_NUM-1];

    wire signed [ACC_DWIDTH-1:0]           row0_bias_ext_w;
    wire signed [ACC_DWIDTH-1:0]           row1_bias_ext_w;
    wire signed [ACC_DWIDTH-1:0]           row2_bias_ext_w;
    wire signed [ACC_DWIDTH-1:0]           row3_bias_ext_w;
    wire signed [ACC_DWIDTH-1:0]           row0_bias_aligned_w;
    wire signed [ACC_DWIDTH-1:0]           row1_bias_aligned_w;
    wire signed [ACC_DWIDTH-1:0]           row2_bias_aligned_w;
    wire signed [ACC_DWIDTH-1:0]           row3_bias_aligned_w;

    wire signed [DATA_DWIDTH-1:0]          quantized_w [0:COL_PE_NUM-1];
    wire                                    quantized_valid_w [0:COL_PE_NUM-1];
    wire [1:0]                              last_row_w;
    wire                                    result_valid_w;

    //-------------------------------------//
    //         Register Declarations       //
    //-------------------------------------//
    reg [COL_PE_NUM-1:0]                   lane_enable_r;
    reg [ROW_PE_NUM-1:0]                   row_enable_r;
    reg [SHIFT_DWIDTH-1:0]                 output_shift_r;
    reg [BANK_SEL_DWIDTH-1:0]              ofmap_bank_offset_r;
    reg                                     serialize_active_r;
    reg [1:0]                               serialize_row_r;

    reg signed [ACC_DWIDTH-1:0]            quantizer_accumulator_r [0:COL_PE_NUM-1];
    reg [COL_PE_NUM-1:0]                   quantizer_valid_r;

    integer                                 logical_lane_r;
    integer                                 physical_bank_r;
    integer                                 select_lane_r;

    genvar                                  row_g;
    genvar                                  col_g;
    genvar                                  quant_g;

    //-------------------------------------//
    //       Shared Row Bias Alignment     //
    //-------------------------------------//
    // Each row broadcasts one bias to sixteen PEs. Align it once per row rather
    // than instantiating the same variable shifter in every PE.
    assign row0_bias_ext_w = {{(ACC_DWIDTH-DATA_DWIDTH){row0_mem_bias_i[DATA_DWIDTH-1]}},
                              row0_mem_bias_i};
    assign row1_bias_ext_w = {{(ACC_DWIDTH-DATA_DWIDTH){row1_mem_bias_i[DATA_DWIDTH-1]}},
                              row1_mem_bias_i};
    assign row2_bias_ext_w = {{(ACC_DWIDTH-DATA_DWIDTH){row2_mem_bias_i[DATA_DWIDTH-1]}},
                              row2_mem_bias_i};
    assign row3_bias_ext_w = {{(ACC_DWIDTH-DATA_DWIDTH){row3_mem_bias_i[DATA_DWIDTH-1]}},
                              row3_mem_bias_i};

    assign row0_bias_aligned_w = $signed(row0_bias_ext_w) <<< output_shift_i;
    assign row1_bias_aligned_w = $signed(row1_bias_ext_w) <<< output_shift_i;
    assign row2_bias_aligned_w = $signed(row2_bias_ext_w) <<< output_shift_i;
    assign row3_bias_aligned_w = $signed(row3_bias_ext_w) <<< output_shift_i;

    //-------------------------------------//
    //               PE Array              //
    //-------------------------------------//
    generate
        for (row_g = 0; row_g < ROW_PE_NUM; row_g = row_g + 1) begin : gen_row
            for (col_g = 0; col_g < COL_PE_NUM; col_g = col_g + 1) begin : gen_col
                localparam integer PE_IDX = (row_g * COL_PE_NUM) + col_g;

                PE #(
                    .DATA_DWIDTH (DATA_DWIDTH),
                    .ACC_DWIDTH  (ACC_DWIDTH)
                ) u_pe (
                    .CLK                  (CLK),
                    .RST                  (RST),
                    .first_ifmap_i        (first_ifmap_i),
                    .last_ifmap_i         (last_ifmap_i),
                    .execute_i            (execute_i),
                    .lane_enable_i        (lane_enable_i[col_g] && row_enable_i[row_g]),
                    .north_ifmap_i        (ifmap_vector_i[(col_g*DATA_DWIDTH) +: DATA_DWIDTH]),
                    .north_ifmap_valid_i  (1'b1),
                    .east_ifmap_i         ({DATA_DWIDTH{1'b0}}),
                    .east_ifmap_valid_i   (1'b0),
                    .south_ifmap_o        (south_ifmap_w[PE_IDX]),
                    .south_ifmap_valid_o  (south_ifmap_valid_w[PE_IDX]),
                    .west_ifmap_o         (west_ifmap_w[PE_IDX]),
                    .west_ifmap_valid_o   (west_ifmap_valid_w[PE_IDX]),
                    .mem_weight_i         ((row_g == 0) ? row0_mem_weight_i :
                                           (row_g == 1) ? row1_mem_weight_i :
                                           (row_g == 2) ? row2_mem_weight_i :
                                                          row3_mem_weight_i),
                    .mem_weight_valid_i   ((row_g == 0) ? row0_mem_weight_valid_i :
                                           (row_g == 1) ? row1_mem_weight_valid_i :
                                           (row_g == 2) ? row2_mem_weight_valid_i :
                                                          row3_mem_weight_valid_i),
                    .mem_bias_aligned_i   ((row_g == 0) ? row0_bias_aligned_w :
                                           (row_g == 1) ? row1_bias_aligned_w :
                                           (row_g == 2) ? row2_bias_aligned_w :
                                                          row3_bias_aligned_w),
                    .mem_bias_valid_i     ((row_g == 0) ? row0_mem_bias_valid_i :
                                           (row_g == 1) ? row1_mem_bias_valid_i :
                                           (row_g == 2) ? row2_mem_bias_valid_i :
                                                          row3_mem_bias_valid_i),
                    .acc_ofmap_o          (acc_ofmap_w[PE_IDX]),
                    .acc_ofmap_valid_o    (acc_ofmap_valid_w[PE_IDX])
                );
            end
        end
    endgenerate

    //-------------------------------------//
    //       Row-Serialized Quantizer      //
    //-------------------------------------//
    assign result_valid_w = acc_ofmap_valid_w[0] |
                            acc_ofmap_valid_w[COL_PE_NUM] |
                            acc_ofmap_valid_w[(2*COL_PE_NUM)] |
                            acc_ofmap_valid_w[(3*COL_PE_NUM)];
    assign last_row_w     = find_last_row(row_enable_r);

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            lane_enable_r       <= {COL_PE_NUM{1'b0}};
            row_enable_r        <= {ROW_PE_NUM{1'b0}};
            output_shift_r      <= {SHIFT_DWIDTH{1'b0}};
            ofmap_bank_offset_r <= {BANK_SEL_DWIDTH{1'b0}};
            serialize_active_r  <= 1'b0;
            serialize_row_r     <= 2'd0;
        end
        else begin
            if (result_valid_w && !serialize_active_r) begin
                lane_enable_r       <= lane_enable_i;
                row_enable_r        <= row_enable_i;
                output_shift_r      <= output_shift_i;
                ofmap_bank_offset_r <= ofmap_bank_offset_i;
                serialize_active_r  <= 1'b1;
                serialize_row_r     <= 2'd0;
            end
            else if (serialize_active_r) begin
                if (serialize_row_r == last_row_w) begin
                    serialize_active_r <= 1'b0;
                    serialize_row_r    <= 2'd0;
                end
                else begin
                    serialize_row_r <= serialize_row_r + 1'b1;
                end
            end
        end
    end

    // Select one PE row for the sixteen shared quantizers. Explicit row cases
    // avoid a synthesized multiply in the variable array index.
    always @(*) begin
        quantizer_valid_r = {COL_PE_NUM{1'b0}};

        for (select_lane_r = 0;
             select_lane_r < COL_PE_NUM;
             select_lane_r = select_lane_r + 1) begin
            quantizer_accumulator_r[select_lane_r] = {ACC_DWIDTH{1'b0}};

            case (serialize_row_r)
                2'd0: quantizer_accumulator_r[select_lane_r] =
                           acc_ofmap_w[select_lane_r];
                2'd1: quantizer_accumulator_r[select_lane_r] =
                           acc_ofmap_w[COL_PE_NUM + select_lane_r];
                2'd2: quantizer_accumulator_r[select_lane_r] =
                           acc_ofmap_w[(2*COL_PE_NUM) + select_lane_r];
                2'd3: quantizer_accumulator_r[select_lane_r] =
                           acc_ofmap_w[(3*COL_PE_NUM) + select_lane_r];
                default: quantizer_accumulator_r[select_lane_r] =
                             {ACC_DWIDTH{1'b0}};
            endcase

            if (serialize_active_r &&
                row_enable_r[serialize_row_r] &&
                lane_enable_r[select_lane_r]) begin
                quantizer_valid_r[select_lane_r] = 1'b1;
            end
        end
    end

    generate
        for (quant_g = 0; quant_g < COL_PE_NUM; quant_g = quant_g + 1) begin : gen_quantizer
            Fixed_Point_Quantizer #(
                .DATA_DWIDTH  (DATA_DWIDTH),
                .ACC_DWIDTH   (ACC_DWIDTH),
                .SHIFT_DWIDTH (SHIFT_DWIDTH)
            ) u_fixed_point_quantizer (
                .CLK             (CLK),
                .RST             (RST),
                .valid_i         (quantizer_valid_r[quant_g]),
                .accumulator_i   (quantizer_accumulator_r[quant_g]),
                .output_shift_i  (output_shift_r),
                .quantized_o     (quantized_w[quant_g]),
                .valid_o         (quantized_valid_w[quant_g])
            );
        end
    endgenerate

    //-------------------------------------//
    //          OFMAP Bank Rotator         //
    //-------------------------------------//
    always @(*) begin
        bank_mem_ofmap_o       = {(FM_BANK_NUM*DATA_DWIDTH){1'b0}};
        bank_mem_ofmap_valid_o = {FM_BANK_NUM{1'b0}};
        physical_bank_r        = 0;

        for (logical_lane_r = 0;
             logical_lane_r < COL_PE_NUM;
             logical_lane_r = logical_lane_r + 1) begin
            physical_bank_r = {28'd0, ofmap_bank_offset_r} + logical_lane_r;

            if (physical_bank_r >= FM_BANK_NUM) begin
                physical_bank_r = physical_bank_r - FM_BANK_NUM;
            end

            bank_mem_ofmap_o[(physical_bank_r*DATA_DWIDTH) +: DATA_DWIDTH] =
                quantized_w[logical_lane_r];
            bank_mem_ofmap_valid_o[physical_bank_r] =
                quantized_valid_w[logical_lane_r];
        end
    end

endmodule

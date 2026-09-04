`timescale 1 ns / 1 ps

module PE #(
    parameter DATA_DWIDTH = 16,
    parameter ACC_DWIDTH  = 48
)(
    input  wire                              CLK,
    input  wire                              RST,

    //================================//
    //             Control            //
    //================================//
    input  wire                              first_ifmap_i,
    input  wire                              last_ifmap_i,
    input  wire                              execute_i,
    input  wire                              lane_enable_i,

    //================================//
    //          North IFMAP           //
    //================================//
    input  wire signed [DATA_DWIDTH-1:0]     north_ifmap_i,
    input  wire                              north_ifmap_valid_i,

    //================================//
    //           East IFMAP           //
    //================================//
    input  wire signed [DATA_DWIDTH-1:0]     east_ifmap_i,
    input  wire                              east_ifmap_valid_i,

    //================================//
    //         Forward Outputs        //
    //================================//
    output reg  signed [DATA_DWIDTH-1:0]     south_ifmap_o,
    output reg                               south_ifmap_valid_o,
    output reg  signed [DATA_DWIDTH-1:0]     west_ifmap_o,
    output reg                               west_ifmap_valid_o,

    //================================//
    //           Weight / Bias        //
    //================================//
    input  wire signed [DATA_DWIDTH-1:0]     mem_weight_i,
    input  wire                              mem_weight_valid_i,
    input  wire signed [ACC_DWIDTH-1:0]      mem_bias_aligned_i,
    input  wire                              mem_bias_valid_i,

    //================================//
    //       Full-Precision OFMAP      //
    //================================//
    output reg  signed [ACC_DWIDTH-1:0]      acc_ofmap_o,
    output reg                               acc_ofmap_valid_o
);

    //-------------------------------------//
    //          Wire Declarations          //
    //-------------------------------------//
    wire signed [DATA_DWIDTH-1:0]          ifmap_in_w;
    wire                                    ifmap_valid_w;
    wire                                    mac_issue_w;
    wire signed [(2*DATA_DWIDTH)-1:0]      mult_product_w;
    wire                                    mult_product_valid_w;
    wire signed [ACC_DWIDTH-1:0]           mult_ext_w;
    wire signed [ACC_DWIDTH-1:0]           accumulator_base_w;
    wire signed [ACC_DWIDTH-1:0]           accumulator_next_w;

    //-------------------------------------//
    //         Register Declarations       //
    //-------------------------------------//
    reg signed [ACC_DWIDTH-1:0]            accumulator_r;
    reg                                     first_ifmap_stage1_r;
    reg                                     first_ifmap_stage2_r;
    reg                                     last_ifmap_stage1_r;
    reg                                     last_ifmap_stage2_r;
    reg                                     bias_valid_stage1_r;
    reg                                     bias_valid_stage2_r;
    reg signed [ACC_DWIDTH-1:0]             bias_stage1_r;
    reg signed [ACC_DWIDTH-1:0]             bias_stage2_r;

    //-------------------------------------//
    //            Input Select             //
    //-------------------------------------//
    assign ifmap_in_w = north_ifmap_valid_i ? north_ifmap_i :
                        east_ifmap_valid_i  ? east_ifmap_i  :
                                               {DATA_DWIDTH{1'b0}};

    assign ifmap_valid_w = north_ifmap_valid_i | east_ifmap_valid_i;
    assign mac_issue_w   = execute_i &&
                           lane_enable_i &&
                           ifmap_valid_w &&
                           mem_weight_valid_i;

    //-------------------------------------//
    //      Two-Stage 16x16 Multiplier     //
    //-------------------------------------//
    Fixed_Point_Multiplier #(
        .DATA_DWIDTH (DATA_DWIDTH)
    ) u_fixed_point_multiplier (
        .CLK          (CLK),
        .RST          (RST),
        .valid_i      (mac_issue_w),
        .operand_a_i  (ifmap_in_w),
        .operand_b_i  (mem_weight_i),
        .product_o    (mult_product_w),
        .valid_o      (mult_product_valid_w)
    );

    assign mult_ext_w = {{(ACC_DWIDTH-(2*DATA_DWIDTH)){
                            mult_product_w[(2*DATA_DWIDTH)-1]}},
                         mult_product_w};

    // Bias is aligned once per PEA row, rather than shifted independently in
    // all sixteen PEs of the row.
    assign accumulator_base_w = first_ifmap_stage2_r ?
                                (bias_valid_stage2_r ? bias_stage2_r :
                                                         {ACC_DWIDTH{1'b0}}) :
                                accumulator_r;

    assign accumulator_next_w = accumulator_base_w + mult_ext_w;

    //-------------------------------------//
    //         Metadata Pipeline           //
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            first_ifmap_stage1_r <= 1'b0;
            first_ifmap_stage2_r <= 1'b0;
            last_ifmap_stage1_r  <= 1'b0;
            last_ifmap_stage2_r  <= 1'b0;
            bias_valid_stage1_r  <= 1'b0;
            bias_valid_stage2_r  <= 1'b0;
            bias_stage1_r        <= {ACC_DWIDTH{1'b0}};
            bias_stage2_r        <= {ACC_DWIDTH{1'b0}};
        end
        else begin
            first_ifmap_stage1_r <= first_ifmap_i;
            first_ifmap_stage2_r <= first_ifmap_stage1_r;
            last_ifmap_stage1_r  <= last_ifmap_i;
            last_ifmap_stage2_r  <= last_ifmap_stage1_r;
            bias_valid_stage1_r  <= mem_bias_valid_i;
            bias_valid_stage2_r  <= bias_valid_stage1_r;
            bias_stage1_r        <= mem_bias_aligned_i;
            bias_stage2_r        <= bias_stage1_r;
        end
    end

    //-------------------------------------//
    //        Accumulator / Result          //
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            accumulator_r     <= {ACC_DWIDTH{1'b0}};
            acc_ofmap_o        <= {ACC_DWIDTH{1'b0}};
            acc_ofmap_valid_o  <= 1'b0;
        end
        else begin
            acc_ofmap_valid_o <= 1'b0;

            if (mult_product_valid_w) begin
                accumulator_r <= accumulator_next_w;

                if (last_ifmap_stage2_r) begin
                    acc_ofmap_o       <= accumulator_next_w;
                    acc_ofmap_valid_o <= 1'b1;
                end
            end
        end
    end

    //-------------------------------------//
    //          Forward Registers          //
    //-------------------------------------//
    // Retained to preserve the existing PE interface and future systolic
    // routing option. The present PEA drives every PE from its north input, so
    // synthesis removes this unused forwarding network.
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            south_ifmap_o       <= {DATA_DWIDTH{1'b0}};
            south_ifmap_valid_o <= 1'b0;
            west_ifmap_o        <= {DATA_DWIDTH{1'b0}};
            west_ifmap_valid_o  <= 1'b0;
        end
        else if (execute_i) begin
            south_ifmap_o       <= ifmap_in_w;
            south_ifmap_valid_o <= ifmap_valid_w;
            west_ifmap_o        <= ifmap_in_w;
            west_ifmap_valid_o  <= ifmap_valid_w;
        end
        else begin
            south_ifmap_o       <= {DATA_DWIDTH{1'b0}};
            south_ifmap_valid_o <= 1'b0;
            west_ifmap_o        <= {DATA_DWIDTH{1'b0}};
            west_ifmap_valid_o  <= 1'b0;
        end
    end

endmodule

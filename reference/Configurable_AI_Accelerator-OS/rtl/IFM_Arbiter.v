`timescale 1 ns / 1 ps

module IFM_Arbiter #(
    parameter DWIDTH          = 16,
    parameter FM_BANK_NUM     = 16,
    parameter BANK_SEL_DWIDTH = 4
)(
    input  wire                                  CLK,
    input  wire                                  RST,

    //================================//
    //         From FM Memory         //
    //================================//
    input  wire [(FM_BANK_NUM*DWIDTH)-1:0]       bank_mem_ifmap_i,

    //================================//
    //         From Controller        //
    //================================//
    input  wire                                  fetch_i,
    input  wire [FM_BANK_NUM-1:0]                ifm_lane_valid_i,
    input  wire [BANK_SEL_DWIDTH-1:0]            ifm_bank_offset_i,

    //================================//
    //       Rotated Logical Lanes    //
    //================================//
    output reg  [(FM_BANK_NUM*DWIDTH)-1:0]       ifm_vector_o,
    output wire                                  ifm_valid_o
);

    //-------------------------------------//
    //         Register Declarations       //
    //-------------------------------------//
    reg                                           fetch_valid_r;
    reg [FM_BANK_NUM-1:0]                         ifm_lane_valid_r;
    reg [BANK_SEL_DWIDTH-1:0]                     ifm_bank_offset_r;

    integer                                       logical_lane_r;
    integer                                       physical_bank_r;

    //-------------------------------------//
    //       Request / BRAM Alignment      //
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            fetch_valid_r     <= 1'b0;
            ifm_lane_valid_r  <= {FM_BANK_NUM{1'b0}};
            ifm_bank_offset_r <= {BANK_SEL_DWIDTH{1'b0}};
        end
        else begin
            fetch_valid_r <= fetch_i;

            if (fetch_i) begin
                ifm_lane_valid_r  <= ifm_lane_valid_i;
                ifm_bank_offset_r <= ifm_bank_offset_i;
            end
        end
    end

    assign ifm_valid_o = fetch_valid_r;

    //-------------------------------------//
    //          Global Bank Rotator        //
    //-------------------------------------//
    always @(*) begin
        ifm_vector_o   = {(FM_BANK_NUM*DWIDTH){1'b0}};
        physical_bank_r = 0;

        if (fetch_valid_r) begin
            for (logical_lane_r = 0;
                 logical_lane_r < FM_BANK_NUM;
                 logical_lane_r = logical_lane_r + 1) begin
                physical_bank_r = {28'd0, ifm_bank_offset_r} + logical_lane_r;

                if (physical_bank_r >= FM_BANK_NUM) begin
                    physical_bank_r = physical_bank_r - FM_BANK_NUM;
                end

                if (ifm_lane_valid_r[logical_lane_r]) begin
                    ifm_vector_o[(logical_lane_r*DWIDTH) +: DWIDTH] =
                        bank_mem_ifmap_i[(physical_bank_r*DWIDTH) +: DWIDTH];
                end
            end
        end
    end

endmodule

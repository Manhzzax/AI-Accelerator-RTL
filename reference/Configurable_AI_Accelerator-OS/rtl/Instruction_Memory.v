`timescale 1 ns / 1 ps

module Instruction_Memory #(
    parameter AWIDTH          = 12,
    parameter MEM_AWIDTH      = 8,
    parameter DWIDTH          = 64,
    parameter USE_ASIC_SRAM   = 0
)(
    input  wire                 CLK,

    //================================//
    //          From Arbiter          //
    //================================//
    input  wire                 arbiter_IM_wvalid_i,
    input  wire [AWIDTH-1:0]    arbiter_IM_waddr_i,
    input  wire [DWIDTH-1:0]    arbiter_IM_wdata_i,

    //================================//
    //         From Controller        //
    //================================//
    input  wire                 ctrl_rd_en_i,
    input  wire [AWIDTH-1:0]    ctrl_addr_i,

    //================================//
    //          To Controller         //
    //================================//
    output wire [DWIDTH-1:0]    instruction_o,
    output wire                 instruction_valid_o
);

    wire [DWIDTH-1:0]           instruction_dout_w;
    wire [MEM_AWIDTH-1:0]       arbiter_mem_addr_w;
    wire [MEM_AWIDTH-1:0]       ctrl_mem_addr_w;
    reg                         ctrl_rd_en_r;

    assign arbiter_mem_addr_w = arbiter_IM_waddr_i[MEM_AWIDTH-1:0];
    assign ctrl_mem_addr_w    = ctrl_addr_i[MEM_AWIDTH-1:0];

    assign instruction_o       = ctrl_rd_en_r ? instruction_dout_w : {DWIDTH{1'b0}};
    assign instruction_valid_o = ctrl_rd_en_r;

    always @(posedge CLK) begin
        ctrl_rd_en_r <= ctrl_rd_en_i;
    end

    Dual_Port_BRAM #(
        .AWIDTH        (MEM_AWIDTH),
        .DWIDTH        (DWIDTH),
        .USE_ASIC_SRAM (USE_ASIC_SRAM)
    ) u_instruction_mem (
        .CLK             (CLK),
        .port_a_en_i     (arbiter_IM_wvalid_i),
        .port_a_we_i     (arbiter_IM_wvalid_i),
        .port_a_addr_i   (arbiter_mem_addr_w),
        .port_a_data_i   (arbiter_IM_wdata_i),
        .port_a_data_o   (),
        .port_b_en_i     (ctrl_rd_en_i),
        .port_b_we_i     (1'b0),
        .port_b_addr_i   (ctrl_mem_addr_w),
        .port_b_data_i   ({DWIDTH{1'b0}}),
        .port_b_data_o   (instruction_dout_w)
    );

endmodule

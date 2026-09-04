`timescale 1 ns / 1 ps

module Weight_Bank_Memory #(
    parameter AWIDTH          = 12,
    parameter MEM_AWIDTH      = 12,
    parameter DWIDTH          = 16,
    parameter NBANKS          = 4,
    parameter TOTAL_DWIDTH    = NBANKS * DWIDTH,
    parameter USE_ASIC_SRAM   = 0
)(
    input  wire                         CLK,

    input  wire                         arbiter_WM_wvalid_i,
    input  wire [AWIDTH-1:0]            arbiter_WM_waddr_i,
    input  wire [TOTAL_DWIDTH-1:0]      arbiter_WM_wdata_i,

    input  wire                         ctrl_bank0_rd_en_i,
    input  wire                         ctrl_bank1_rd_en_i,
    input  wire                         ctrl_bank2_rd_en_i,
    input  wire                         ctrl_bank3_rd_en_i,

    input  wire [AWIDTH-1:0]            ctrl_bank0_addr_i,
    input  wire [AWIDTH-1:0]            ctrl_bank1_addr_i,
    input  wire [AWIDTH-1:0]            ctrl_bank2_addr_i,
    input  wire [AWIDTH-1:0]            ctrl_bank3_addr_i,

    output wire [DWIDTH-1:0]            bank0_mem_weight_o,
    output wire [DWIDTH-1:0]            bank1_mem_weight_o,
    output wire [DWIDTH-1:0]            bank2_mem_weight_o,
    output wire [DWIDTH-1:0]            bank3_mem_weight_o,

    output wire                         bank0_mem_weight_valid_o,
    output wire                         bank1_mem_weight_valid_o,
    output wire                         bank2_mem_weight_valid_o,
    output wire                         bank3_mem_weight_valid_o
);

    wire [DWIDTH-1:0]                   bank0_dout_w;
    wire [DWIDTH-1:0]                   bank1_dout_w;
    wire [DWIDTH-1:0]                   bank2_dout_w;
    wire [DWIDTH-1:0]                   bank3_dout_w;

    wire [MEM_AWIDTH-1:0]               arbiter_mem_addr_w;
    wire [MEM_AWIDTH-1:0]               ctrl_bank0_mem_addr_w;
    wire [MEM_AWIDTH-1:0]               ctrl_bank1_mem_addr_w;
    wire [MEM_AWIDTH-1:0]               ctrl_bank2_mem_addr_w;
    wire [MEM_AWIDTH-1:0]               ctrl_bank3_mem_addr_w;

    reg                                 ctrl_bank0_rd_en_r;
    reg                                 ctrl_bank1_rd_en_r;
    reg                                 ctrl_bank2_rd_en_r;
    reg                                 ctrl_bank3_rd_en_r;

    assign arbiter_mem_addr_w    = arbiter_WM_waddr_i[MEM_AWIDTH-1:0];
    assign ctrl_bank0_mem_addr_w = ctrl_bank0_addr_i[MEM_AWIDTH-1:0];
    assign ctrl_bank1_mem_addr_w = ctrl_bank1_addr_i[MEM_AWIDTH-1:0];
    assign ctrl_bank2_mem_addr_w = ctrl_bank2_addr_i[MEM_AWIDTH-1:0];
    assign ctrl_bank3_mem_addr_w = ctrl_bank3_addr_i[MEM_AWIDTH-1:0];

    always @(posedge CLK) begin
        ctrl_bank0_rd_en_r <= ctrl_bank0_rd_en_i;
        ctrl_bank1_rd_en_r <= ctrl_bank1_rd_en_i;
        ctrl_bank2_rd_en_r <= ctrl_bank2_rd_en_i;
        ctrl_bank3_rd_en_r <= ctrl_bank3_rd_en_i;
    end

    assign bank0_mem_weight_valid_o = ctrl_bank0_rd_en_r;
    assign bank1_mem_weight_valid_o = ctrl_bank1_rd_en_r;
    assign bank2_mem_weight_valid_o = ctrl_bank2_rd_en_r;
    assign bank3_mem_weight_valid_o = ctrl_bank3_rd_en_r;

    assign bank0_mem_weight_o = ctrl_bank0_rd_en_r ? bank0_dout_w : {DWIDTH{1'b0}};
    assign bank1_mem_weight_o = ctrl_bank1_rd_en_r ? bank1_dout_w : {DWIDTH{1'b0}};
    assign bank2_mem_weight_o = ctrl_bank2_rd_en_r ? bank2_dout_w : {DWIDTH{1'b0}};
    assign bank3_mem_weight_o = ctrl_bank3_rd_en_r ? bank3_dout_w : {DWIDTH{1'b0}};

    Dual_Port_BRAM #(
        .AWIDTH        (MEM_AWIDTH),
        .DWIDTH        (DWIDTH),
        .USE_ASIC_SRAM (USE_ASIC_SRAM)
    ) u_bank0 (
        .CLK           (CLK),
        .port_a_en_i   (arbiter_WM_wvalid_i),
        .port_a_we_i   (arbiter_WM_wvalid_i),
        .port_a_addr_i (arbiter_mem_addr_w),
        .port_a_data_i (arbiter_WM_wdata_i[(DWIDTH*1)-1:(DWIDTH*0)]),
        .port_a_data_o (),
        .port_b_en_i   (ctrl_bank0_rd_en_i),
        .port_b_we_i   (1'b0),
        .port_b_addr_i (ctrl_bank0_mem_addr_w),
        .port_b_data_i ({DWIDTH{1'b0}}),
        .port_b_data_o (bank0_dout_w)
    );

    Dual_Port_BRAM #(
        .AWIDTH        (MEM_AWIDTH),
        .DWIDTH        (DWIDTH),
        .USE_ASIC_SRAM (USE_ASIC_SRAM)
    ) u_bank1 (
        .CLK           (CLK),
        .port_a_en_i   (arbiter_WM_wvalid_i),
        .port_a_we_i   (arbiter_WM_wvalid_i),
        .port_a_addr_i (arbiter_mem_addr_w),
        .port_a_data_i (arbiter_WM_wdata_i[(DWIDTH*2)-1:(DWIDTH*1)]),
        .port_a_data_o (),
        .port_b_en_i   (ctrl_bank1_rd_en_i),
        .port_b_we_i   (1'b0),
        .port_b_addr_i (ctrl_bank1_mem_addr_w),
        .port_b_data_i ({DWIDTH{1'b0}}),
        .port_b_data_o (bank1_dout_w)
    );

    Dual_Port_BRAM #(
        .AWIDTH        (MEM_AWIDTH),
        .DWIDTH        (DWIDTH),
        .USE_ASIC_SRAM (USE_ASIC_SRAM)
    ) u_bank2 (
        .CLK           (CLK),
        .port_a_en_i   (arbiter_WM_wvalid_i),
        .port_a_we_i   (arbiter_WM_wvalid_i),
        .port_a_addr_i (arbiter_mem_addr_w),
        .port_a_data_i (arbiter_WM_wdata_i[(DWIDTH*3)-1:(DWIDTH*2)]),
        .port_a_data_o (),
        .port_b_en_i   (ctrl_bank2_rd_en_i),
        .port_b_we_i   (1'b0),
        .port_b_addr_i (ctrl_bank2_mem_addr_w),
        .port_b_data_i ({DWIDTH{1'b0}}),
        .port_b_data_o (bank2_dout_w)
    );

    Dual_Port_BRAM #(
        .AWIDTH        (MEM_AWIDTH),
        .DWIDTH        (DWIDTH),
        .USE_ASIC_SRAM (USE_ASIC_SRAM)
    ) u_bank3 (
        .CLK           (CLK),
        .port_a_en_i   (arbiter_WM_wvalid_i),
        .port_a_we_i   (arbiter_WM_wvalid_i),
        .port_a_addr_i (arbiter_mem_addr_w),
        .port_a_data_i (arbiter_WM_wdata_i[(DWIDTH*4)-1:(DWIDTH*3)]),
        .port_a_data_o (),
        .port_b_en_i   (ctrl_bank3_rd_en_i),
        .port_b_we_i   (1'b0),
        .port_b_addr_i (ctrl_bank3_mem_addr_w),
        .port_b_data_i ({DWIDTH{1'b0}}),
        .port_b_data_o (bank3_dout_w)
    );

endmodule

`timescale 1 ns / 1 ps

module Ping_Pong_FMAP_Bank_Memory #(
    parameter AWIDTH          = 12,
    parameter MEM_AWIDTH      = 10,
    parameter DWIDTH          = 16,
    parameter NBANKS          = 16,
    parameter HOST_LANES      = 4,
    parameter HOST_GROUP_BITS = 2,
    parameter TOTAL_DWIDTH    = HOST_LANES * DWIDTH,
    parameter USE_ASIC_SRAM   = 0
)(
    input  wire                              CLK,

    input  wire                              arbiter_FM_wvalid_i,
    input  wire [AWIDTH-1:0]                 arbiter_FM_waddr_i,
    input  wire [TOTAL_DWIDTH-1:0]           arbiter_FM_wdata_i,

    input  wire                              arbiter_FM_arvalid_i,
    input  wire [AWIDTH-1:0]                 arbiter_FM_raddr_i,
    output reg  [TOTAL_DWIDTH-1:0]           arbiter_FM_rdata_o,

    input  wire [NBANKS-1:0]                 ctrl_bank_rd_en_i,
    input  wire [NBANKS-1:0]                 ctrl_bank_wr_en_i,
    input  wire [(NBANKS*AWIDTH)-1:0]        ctrl_bank_addr_i,

    input  wire [(NBANKS*DWIDTH)-1:0]        bank_mem_ofmap_i,
    input  wire [NBANKS-1:0]                 bank_mem_ofmap_valid_i,

    output wire [(NBANKS*DWIDTH)-1:0]        bank_mem_ifmap_o,
    output wire [NBANKS-1:0]                 bank_mem_ifmap_valid_o
);

    wire                                    arbiter_access_w;
    wire [AWIDTH-1:0]                       arbiter_word_addr_w;
    wire [HOST_GROUP_BITS-1:0]              arbiter_group_w;
    wire [MEM_AWIDTH-1:0]                   arbiter_bank_addr_w;

    wire [(NBANKS*DWIDTH)-1:0]              arbiter_bank_dout_w;
    wire [(NBANKS*DWIDTH)-1:0]              ctrl_bank_dout_w;
    wire [NBANKS-1:0]                       ctrl_bank_en_w;
    wire [NBANKS-1:0]                       ctrl_bank_we_w;

    reg [NBANKS-1:0]                        ctrl_bank_rd_en_r;
    reg [HOST_GROUP_BITS-1:0]               arbiter_group_r;

    integer                                 host_lane_r;
    integer                                 host_bank_idx_r;
    genvar                                  bank_g;

    // Four 16-bit host lanes address one of four physical bank groups.
    // With MEM_AWIDTH=10, the host-local FM word address therefore needs
    // 10 + 2 = 12 bits to reach all 1024 rows of all 16 banks.
    assign arbiter_access_w    = arbiter_FM_wvalid_i | arbiter_FM_arvalid_i;
    assign arbiter_word_addr_w = arbiter_FM_wvalid_i ? arbiter_FM_waddr_i :
                                                        arbiter_FM_raddr_i;
    assign arbiter_group_w     = arbiter_word_addr_w[HOST_GROUP_BITS-1:0];
    assign arbiter_bank_addr_w =
        arbiter_word_addr_w[MEM_AWIDTH+HOST_GROUP_BITS-1:HOST_GROUP_BITS];

    always @(posedge CLK) begin
        ctrl_bank_rd_en_r <= ctrl_bank_rd_en_i;

        if (arbiter_access_w) begin
            arbiter_group_r <= arbiter_group_w;
        end
    end

    always @(*) begin
        arbiter_FM_rdata_o = {TOTAL_DWIDTH{1'b0}};

        for (host_lane_r = 0; host_lane_r < HOST_LANES; host_lane_r = host_lane_r + 1) begin
            host_bank_idx_r = (arbiter_group_r * HOST_LANES) + host_lane_r;
            arbiter_FM_rdata_o[(host_lane_r*DWIDTH) +: DWIDTH] =
                arbiter_bank_dout_w[(host_bank_idx_r*DWIDTH) +: DWIDTH];
        end
    end

    generate
        for (bank_g = 0; bank_g < NBANKS; bank_g = bank_g + 1) begin : gen_fm_bank
            localparam integer BANK_GROUP = bank_g / HOST_LANES;
            localparam integer BANK_LANE  = bank_g % HOST_LANES;

            wire [MEM_AWIDTH-1:0] ctrl_bank_mem_addr_w;

            assign ctrl_bank_mem_addr_w =
                ctrl_bank_addr_i[(bank_g*AWIDTH) +: MEM_AWIDTH];

            assign ctrl_bank_we_w[bank_g] = ctrl_bank_wr_en_i[bank_g] &
                                             bank_mem_ofmap_valid_i[bank_g];

            assign ctrl_bank_en_w[bank_g] = ctrl_bank_rd_en_i[bank_g] |
                                             ctrl_bank_we_w[bank_g];

            assign bank_mem_ifmap_valid_o[bank_g] = ctrl_bank_rd_en_r[bank_g];

            assign bank_mem_ifmap_o[(bank_g*DWIDTH) +: DWIDTH] =
                ctrl_bank_rd_en_r[bank_g] ?
                ctrl_bank_dout_w[(bank_g*DWIDTH) +: DWIDTH] :
                {DWIDTH{1'b0}};

            Dual_Port_BRAM #(
                .AWIDTH        (MEM_AWIDTH),
                .DWIDTH        (DWIDTH),
                .USE_ASIC_SRAM (USE_ASIC_SRAM)
            ) u_bank (
                .CLK           (CLK),
                .port_a_en_i   (arbiter_access_w &&
                                 (arbiter_group_w == BANK_GROUP[HOST_GROUP_BITS-1:0])),
                .port_a_we_i   (arbiter_FM_wvalid_i &&
                                 (arbiter_group_w == BANK_GROUP[HOST_GROUP_BITS-1:0])),
                .port_a_addr_i (arbiter_bank_addr_w),
                .port_a_data_i (arbiter_FM_wdata_i[(BANK_LANE*DWIDTH) +: DWIDTH]),
                .port_a_data_o (arbiter_bank_dout_w[(bank_g*DWIDTH) +: DWIDTH]),
                .port_b_en_i   (ctrl_bank_en_w[bank_g]),
                .port_b_we_i   (ctrl_bank_we_w[bank_g]),
                .port_b_addr_i (ctrl_bank_mem_addr_w),
                .port_b_data_i (bank_mem_ofmap_i[(bank_g*DWIDTH) +: DWIDTH]),
                .port_b_data_o (ctrl_bank_dout_w[(bank_g*DWIDTH) +: DWIDTH])
            );
        end
    endgenerate

endmodule

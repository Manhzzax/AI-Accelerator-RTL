`timescale 1 ns / 1 ps

module CNN_1D_Core #(
    // Global local-address width. It must cover the largest host-visible
    // memory window. FM host access needs FM_AWIDTH + 2 group bits.
    parameter AWIDTH           = 12,
    parameter IM_AWIDTH        = 8,
    parameter FM_AWIDTH        = 10,
    parameter WM_AWIDTH        = 12,
    parameter BM_AWIDTH        = 8,
    parameter USE_ASIC_SRAM    = 0,
    parameter DWIDTH           = 16,
    parameter INST_DWIDTH      = 64,
    parameter AXI_WADDR_WIDTH  = AWIDTH + 3,
    parameter AXI_RADDR_WIDTH  = AWIDTH + 3,
    parameter AXI_WDATA_DWIDTH = 64,
    parameter AXI_RDATA_DWIDTH = 64,
    parameter EXEC_DEPTH       = 16,
    parameter COL_PE_NUM       = 16,
    parameter ROW_PE_NUM       = 4,
    parameter FM_BANK_NUM      = 16,
    parameter BANK_SEL_DWIDTH  = 4,
    parameter ACC_DWIDTH       = 48,
    parameter SHIFT_DWIDTH     = 6,
    parameter KERNEL_MAX       = 15,
    parameter STRIDE_MAX       = 1
)(
    input  wire                                CLK,
    input  wire                                RST,
    input  wire [AXI_WADDR_WIDTH-1:0]          axi_waddr_i,
    input  wire [AXI_WDATA_DWIDTH-1:0]         axi_wdata_i,
    input  wire                                axi_wvalid_i,
    input  wire [AXI_RADDR_WIDTH-1:0]          axi_raddr_i,
    input  wire                                axi_arvalid_i,
    output wire [AXI_RDATA_DWIDTH-1:0]         axi_rdata_o
);

    //-------------------------------------//
    //          Arbiter Interconnect       //
    //-------------------------------------//
    wire                                   arbiter_load_flag_w;
    wire                                   arbiter_start_flag_w;
    wire                                   arbiter_done_flag_w;
    wire [15:0]                            arbiter_network_input_width_w;
    wire [AWIDTH-1:0]                      arbiter_max_IM_addr_w;

    wire                                   arbiter_IM_wvalid_w;
    wire [AWIDTH-1:0]                      arbiter_IM_waddr_w;
    wire [INST_DWIDTH-1:0]                 arbiter_IM_wdata_w;

    wire                                   arbiter_Ping_FM_wvalid_w;
    wire [AWIDTH-1:0]                      arbiter_Ping_FM_waddr_w;
    wire [AXI_WDATA_DWIDTH-1:0]            arbiter_Ping_FM_wdata_w;
    wire                                   arbiter_Ping_FM_arvalid_w;
    wire [AWIDTH-1:0]                      arbiter_Ping_FM_raddr_w;
    wire [AXI_RDATA_DWIDTH-1:0]            arbiter_Ping_FM_rdata_w;

    wire                                   arbiter_Pong_FM_wvalid_w;
    wire [AWIDTH-1:0]                      arbiter_Pong_FM_waddr_w;
    wire [AXI_WDATA_DWIDTH-1:0]            arbiter_Pong_FM_wdata_w;
    wire                                   arbiter_Pong_FM_arvalid_w;
    wire [AWIDTH-1:0]                      arbiter_Pong_FM_raddr_w;
    wire [AXI_RDATA_DWIDTH-1:0]            arbiter_Pong_FM_rdata_w;

    wire                                   arbiter_WM_wvalid_w;
    wire [AWIDTH-1:0]                      arbiter_WM_waddr_w;
    wire [AXI_WDATA_DWIDTH-1:0]            arbiter_WM_wdata_w;

    wire                                   arbiter_BM_wvalid_w;
    wire [AWIDTH-1:0]                      arbiter_BM_waddr_w;
    wire [AXI_WDATA_DWIDTH-1:0]            arbiter_BM_wdata_w;

    //-------------------------------------//
    //        Controller Interconnect      //
    //-------------------------------------//
    wire [2:0]                             controller_state_w;
    wire                                   controller_complete_w;

    wire                                   instruction_valid_w;
    wire [INST_DWIDTH-1:0]                 instruction_w;
    wire                                   ctrl_IM_rd_en_w;
    wire [AWIDTH-1:0]                      ctrl_IM_addr_w;

    wire                                   ctrl_WM_bank0_rd_en_w;
    wire                                   ctrl_WM_bank1_rd_en_w;
    wire                                   ctrl_WM_bank2_rd_en_w;
    wire                                   ctrl_WM_bank3_rd_en_w;
    wire [AWIDTH-1:0]                      ctrl_WM_bank0_addr_w;
    wire [AWIDTH-1:0]                      ctrl_WM_bank1_addr_w;
    wire [AWIDTH-1:0]                      ctrl_WM_bank2_addr_w;
    wire [AWIDTH-1:0]                      ctrl_WM_bank3_addr_w;

    wire                                   ctrl_BM_bank0_rd_en_w;
    wire                                   ctrl_BM_bank1_rd_en_w;
    wire                                   ctrl_BM_bank2_rd_en_w;
    wire                                   ctrl_BM_bank3_rd_en_w;
    wire [AWIDTH-1:0]                      ctrl_BM_bank0_addr_w;
    wire [AWIDTH-1:0]                      ctrl_BM_bank1_addr_w;
    wire [AWIDTH-1:0]                      ctrl_BM_bank2_addr_w;
    wire [AWIDTH-1:0]                      ctrl_BM_bank3_addr_w;

    wire [FM_BANK_NUM-1:0]                 ctrl_Ping_FM_bank_rd_en_w;
    wire [FM_BANK_NUM-1:0]                 ctrl_Ping_FM_bank_wr_en_w;
    wire [(FM_BANK_NUM*AWIDTH)-1:0]        ctrl_Ping_FM_bank_addr_w;
    wire [FM_BANK_NUM-1:0]                 ctrl_Pong_FM_bank_rd_en_w;
    wire [FM_BANK_NUM-1:0]                 ctrl_Pong_FM_bank_wr_en_w;
    wire [(FM_BANK_NUM*AWIDTH)-1:0]        ctrl_Pong_FM_bank_addr_w;

    wire                                   ifm_fetch_w;
    wire [FM_BANK_NUM-1:0]                 ifm_lane_valid_w;
    wire [BANK_SEL_DWIDTH-1:0]             ifm_bank_offset_w;

    wire                                   first_ifmap_w;
    wire                                   last_ifmap_w;
    wire                                   execute_w;
    wire [COL_PE_NUM-1:0]                  pea_lane_enable_w;
    wire [ROW_PE_NUM-1:0]                  pea_row_enable_w;
    wire [SHIFT_DWIDTH-1:0]                output_shift_w;
    wire [BANK_SEL_DWIDTH-1:0]             ofmap_bank_offset_w;

    wire                                   line_buffer_clear_w;
    wire                                   line_buffer_load_first_w;
    wire                                   line_buffer_load_second_w;
    wire                                   line_buffer_shift_w;

    //-------------------------------------//
    //             Data Paths              //
    //-------------------------------------//
    wire [(FM_BANK_NUM*DWIDTH)-1:0]        ping_ifmap_vector_w;
    wire [FM_BANK_NUM-1:0]                 ping_ifmap_valid_w;
    wire [(FM_BANK_NUM*DWIDTH)-1:0]        pong_ifmap_vector_w;
    wire [FM_BANK_NUM-1:0]                 pong_ifmap_valid_w;
    wire [(FM_BANK_NUM*DWIDTH)-1:0]        physical_ifmap_vector_w;
    wire [(FM_BANK_NUM*DWIDTH)-1:0]        rotated_ifmap_vector_w;
    wire                                   rotated_ifmap_valid_w;
    wire [(COL_PE_NUM*DWIDTH)-1:0]         ifmap_vector_w;

    wire [DWIDTH-1:0]                      bank0_mem_weight_w;
    wire [DWIDTH-1:0]                      bank1_mem_weight_w;
    wire [DWIDTH-1:0]                      bank2_mem_weight_w;
    wire [DWIDTH-1:0]                      bank3_mem_weight_w;
    wire                                   bank0_mem_weight_valid_w;
    wire                                   bank1_mem_weight_valid_w;
    wire                                   bank2_mem_weight_valid_w;
    wire                                   bank3_mem_weight_valid_w;

    wire [DWIDTH-1:0]                      bank0_mem_bias_w;
    wire [DWIDTH-1:0]                      bank1_mem_bias_w;
    wire [DWIDTH-1:0]                      bank2_mem_bias_w;
    wire [DWIDTH-1:0]                      bank3_mem_bias_w;
    wire                                   bank0_mem_bias_valid_w;
    wire                                   bank1_mem_bias_valid_w;
    wire                                   bank2_mem_bias_valid_w;
    wire                                   bank3_mem_bias_valid_w;

    wire [(FM_BANK_NUM*DWIDTH)-1:0]        bank_mem_ofmap_w;
    wire [FM_BANK_NUM-1:0]                 bank_mem_ofmap_valid_w;

    //-------------------------------------//
    //            Global Arbiter           //
    //-------------------------------------//
    Global_Arbiter #(
        .MAWIDTH           (AWIDTH),
        .INST_MDWIDTH      (INST_DWIDTH),
        .AXI_WADDR_WIDTH   (AXI_WADDR_WIDTH),
        .AXI_RADDR_WIDTH   (AXI_RADDR_WIDTH),
        .AXI_WDATA_MDWIDTH (AXI_WDATA_DWIDTH),
        .AXI_RDATA_MDWIDTH (AXI_RDATA_DWIDTH)
    ) u_global_arbiter (
        .CLK                        (CLK),
        .RST                        (RST),
        .axi_waddr_i                (axi_waddr_i),
        .axi_wdata_i                (axi_wdata_i),
        .axi_wvalid_i               (axi_wvalid_i),
        .axi_raddr_i                (axi_raddr_i),
        .axi_arvalid_i              (axi_arvalid_i),
        .axi_rdata_o                (axi_rdata_o),
        .direct_load_i              (1'b0),
        .direct_start_i             (1'b0),
        .direct_done_i              (1'b0),
        .state_i                    (controller_state_w),
        .completed_i                (controller_complete_w),
        .load_flag_o                (arbiter_load_flag_w),
        .start_flag_o               (arbiter_start_flag_w),
        .done_flag_o                (arbiter_done_flag_w),
        .network_input_width_o      (arbiter_network_input_width_w),
        .max_IM_addr_o              (arbiter_max_IM_addr_w),
        .arbiter_IM_wvalid_o        (arbiter_IM_wvalid_w),
        .arbiter_IM_waddr_o         (arbiter_IM_waddr_w),
        .arbiter_IM_wdata_o         (arbiter_IM_wdata_w),
        .arbiter_Ping_FM_wvalid_o   (arbiter_Ping_FM_wvalid_w),
        .arbiter_Ping_FM_waddr_o    (arbiter_Ping_FM_waddr_w),
        .arbiter_Ping_FM_wdata_o    (arbiter_Ping_FM_wdata_w),
        .arbiter_Ping_FM_arvalid_o  (arbiter_Ping_FM_arvalid_w),
        .arbiter_Ping_FM_raddr_o    (arbiter_Ping_FM_raddr_w),
        .arbiter_Ping_FM_rdata_i    (arbiter_Ping_FM_rdata_w),
        .arbiter_Pong_FM_wvalid_o   (arbiter_Pong_FM_wvalid_w),
        .arbiter_Pong_FM_waddr_o    (arbiter_Pong_FM_waddr_w),
        .arbiter_Pong_FM_wdata_o    (arbiter_Pong_FM_wdata_w),
        .arbiter_Pong_FM_arvalid_o  (arbiter_Pong_FM_arvalid_w),
        .arbiter_Pong_FM_raddr_o    (arbiter_Pong_FM_raddr_w),
        .arbiter_Pong_FM_rdata_i    (arbiter_Pong_FM_rdata_w),
        .arbiter_WM_wvalid_o        (arbiter_WM_wvalid_w),
        .arbiter_WM_waddr_o         (arbiter_WM_waddr_w),
        .arbiter_WM_wdata_o         (arbiter_WM_wdata_w),
        .arbiter_BM_wvalid_o        (arbiter_BM_wvalid_w),
        .arbiter_BM_waddr_o         (arbiter_BM_waddr_w),
        .arbiter_BM_wdata_o         (arbiter_BM_wdata_w)
    );

    //-------------------------------------//
    //              Controller             //
    //-------------------------------------//
    Controller #(
        .AWIDTH           (AWIDTH),
        .DWIDTH           (DWIDTH),
        .INST_DWIDTH      (INST_DWIDTH),
        .AXI_WDATA_DWIDTH (AXI_WDATA_DWIDTH),
        .EXEC_DEPTH       (EXEC_DEPTH),
        .COL_PE_NUM       (COL_PE_NUM),
        .ROW_PE_NUM       (ROW_PE_NUM),
        .FM_BANK_NUM      (FM_BANK_NUM),
        .BANK_SEL_DWIDTH  (BANK_SEL_DWIDTH),
        .SHIFT_DWIDTH     (SHIFT_DWIDTH)
    ) u_controller (
        .CLK                         (CLK),
        .RST                         (RST),
        .load_flag_i                 (arbiter_load_flag_w),
        .start_flag_i                (arbiter_start_flag_w),
        .done_flag_i                 (arbiter_done_flag_w),
        .network_input_width_i       (arbiter_network_input_width_w),
        .max_IM_addr_i               (arbiter_max_IM_addr_w),
        .state_o                     (controller_state_w),
        .complete_o                  (controller_complete_w),
        .ctrl_WM_bank0_rd_en_o       (ctrl_WM_bank0_rd_en_w),
        .ctrl_WM_bank1_rd_en_o       (ctrl_WM_bank1_rd_en_w),
        .ctrl_WM_bank2_rd_en_o       (ctrl_WM_bank2_rd_en_w),
        .ctrl_WM_bank3_rd_en_o       (ctrl_WM_bank3_rd_en_w),
        .ctrl_WM_bank0_addr_o        (ctrl_WM_bank0_addr_w),
        .ctrl_WM_bank1_addr_o        (ctrl_WM_bank1_addr_w),
        .ctrl_WM_bank2_addr_o        (ctrl_WM_bank2_addr_w),
        .ctrl_WM_bank3_addr_o        (ctrl_WM_bank3_addr_w),
        .ctrl_BM_bank0_rd_en_o       (ctrl_BM_bank0_rd_en_w),
        .ctrl_BM_bank1_rd_en_o       (ctrl_BM_bank1_rd_en_w),
        .ctrl_BM_bank2_rd_en_o       (ctrl_BM_bank2_rd_en_w),
        .ctrl_BM_bank3_rd_en_o       (ctrl_BM_bank3_rd_en_w),
        .ctrl_BM_bank0_addr_o        (ctrl_BM_bank0_addr_w),
        .ctrl_BM_bank1_addr_o        (ctrl_BM_bank1_addr_w),
        .ctrl_BM_bank2_addr_o        (ctrl_BM_bank2_addr_w),
        .ctrl_BM_bank3_addr_o        (ctrl_BM_bank3_addr_w),
        .ctrl_IM_rd_en_o             (ctrl_IM_rd_en_w),
        .ctrl_IM_addr_o              (ctrl_IM_addr_w),
        .instruction_i               (instruction_w),
        .instruction_valid_i         (instruction_valid_w),
        .ctrl_Ping_FM_bank_rd_en_o   (ctrl_Ping_FM_bank_rd_en_w),
        .ctrl_Ping_FM_bank_wr_en_o   (ctrl_Ping_FM_bank_wr_en_w),
        .ctrl_Ping_FM_bank_addr_o    (ctrl_Ping_FM_bank_addr_w),
        .ctrl_Pong_FM_bank_rd_en_o   (ctrl_Pong_FM_bank_rd_en_w),
        .ctrl_Pong_FM_bank_wr_en_o   (ctrl_Pong_FM_bank_wr_en_w),
        .ctrl_Pong_FM_bank_addr_o    (ctrl_Pong_FM_bank_addr_w),
        .ifm_fetch_o                 (ifm_fetch_w),
        .ifm_lane_valid_o            (ifm_lane_valid_w),
        .ifm_bank_offset_o           (ifm_bank_offset_w),
        .bank_mem_ofmap_valid_i      (bank_mem_ofmap_valid_w),
        .first_ifmap_o               (first_ifmap_w),
        .last_ifmap_o                (last_ifmap_w),
        .execute_o                   (execute_w),
        .pea_lane_enable_o           (pea_lane_enable_w),
        .pea_row_enable_o            (pea_row_enable_w),
        .output_shift_o              (output_shift_w),
        .ofmap_bank_offset_o         (ofmap_bank_offset_w),
        .line_buffer_clear_o         (line_buffer_clear_w),
        .line_buffer_load_first_o    (line_buffer_load_first_w),
        .line_buffer_load_second_o   (line_buffer_load_second_w),
        .line_buffer_shift_o         (line_buffer_shift_w)
    );

    //-------------------------------------//
    //              Memories               //
    //-------------------------------------//
    Instruction_Memory #(
        .AWIDTH        (AWIDTH),
        .MEM_AWIDTH    (IM_AWIDTH),
        .DWIDTH        (INST_DWIDTH),
        .USE_ASIC_SRAM (USE_ASIC_SRAM)
    ) u_instruction_memory (
        .CLK                  (CLK),
        .arbiter_IM_wvalid_i  (arbiter_IM_wvalid_w),
        .arbiter_IM_waddr_i   (arbiter_IM_waddr_w),
        .arbiter_IM_wdata_i   (arbiter_IM_wdata_w),
        .ctrl_rd_en_i         (ctrl_IM_rd_en_w),
        .ctrl_addr_i          (ctrl_IM_addr_w),
        .instruction_o        (instruction_w),
        .instruction_valid_o  (instruction_valid_w)
    );

    Weight_Bank_Memory #(
        .AWIDTH        (AWIDTH),
        .MEM_AWIDTH    (WM_AWIDTH),
        .DWIDTH        (DWIDTH),
        .USE_ASIC_SRAM (USE_ASIC_SRAM)
    ) u_weight_memory (
        .CLK                         (CLK),
        .arbiter_WM_wvalid_i         (arbiter_WM_wvalid_w),
        .arbiter_WM_waddr_i          (arbiter_WM_waddr_w),
        .arbiter_WM_wdata_i          (arbiter_WM_wdata_w),
        .ctrl_bank0_rd_en_i          (ctrl_WM_bank0_rd_en_w),
        .ctrl_bank1_rd_en_i          (ctrl_WM_bank1_rd_en_w),
        .ctrl_bank2_rd_en_i          (ctrl_WM_bank2_rd_en_w),
        .ctrl_bank3_rd_en_i          (ctrl_WM_bank3_rd_en_w),
        .ctrl_bank0_addr_i           (ctrl_WM_bank0_addr_w),
        .ctrl_bank1_addr_i           (ctrl_WM_bank1_addr_w),
        .ctrl_bank2_addr_i           (ctrl_WM_bank2_addr_w),
        .ctrl_bank3_addr_i           (ctrl_WM_bank3_addr_w),
        .bank0_mem_weight_o          (bank0_mem_weight_w),
        .bank1_mem_weight_o          (bank1_mem_weight_w),
        .bank2_mem_weight_o          (bank2_mem_weight_w),
        .bank3_mem_weight_o          (bank3_mem_weight_w),
        .bank0_mem_weight_valid_o    (bank0_mem_weight_valid_w),
        .bank1_mem_weight_valid_o    (bank1_mem_weight_valid_w),
        .bank2_mem_weight_valid_o    (bank2_mem_weight_valid_w),
        .bank3_mem_weight_valid_o    (bank3_mem_weight_valid_w)
    );

    Bias_Bank_Memory #(
        .AWIDTH        (AWIDTH),
        .MEM_AWIDTH    (BM_AWIDTH),
        .DWIDTH        (DWIDTH),
        .USE_ASIC_SRAM (USE_ASIC_SRAM)
    ) u_bias_memory (
        .CLK                       (CLK),
        .arbiter_BM_wvalid_i       (arbiter_BM_wvalid_w),
        .arbiter_BM_waddr_i        (arbiter_BM_waddr_w),
        .arbiter_BM_wdata_i        (arbiter_BM_wdata_w),
        .ctrl_bank0_rd_en_i        (ctrl_BM_bank0_rd_en_w),
        .ctrl_bank1_rd_en_i        (ctrl_BM_bank1_rd_en_w),
        .ctrl_bank2_rd_en_i        (ctrl_BM_bank2_rd_en_w),
        .ctrl_bank3_rd_en_i        (ctrl_BM_bank3_rd_en_w),
        .ctrl_bank0_addr_i         (ctrl_BM_bank0_addr_w),
        .ctrl_bank1_addr_i         (ctrl_BM_bank1_addr_w),
        .ctrl_bank2_addr_i         (ctrl_BM_bank2_addr_w),
        .ctrl_bank3_addr_i         (ctrl_BM_bank3_addr_w),
        .bank0_mem_bias_o          (bank0_mem_bias_w),
        .bank1_mem_bias_o          (bank1_mem_bias_w),
        .bank2_mem_bias_o          (bank2_mem_bias_w),
        .bank3_mem_bias_o          (bank3_mem_bias_w),
        .bank0_mem_bias_valid_o    (bank0_mem_bias_valid_w),
        .bank1_mem_bias_valid_o    (bank1_mem_bias_valid_w),
        .bank2_mem_bias_valid_o    (bank2_mem_bias_valid_w),
        .bank3_mem_bias_valid_o    (bank3_mem_bias_valid_w)
    );

    Ping_Pong_FMAP_Bank_Memory #(
        .AWIDTH          (AWIDTH),
        .MEM_AWIDTH      (FM_AWIDTH),
        .DWIDTH          (DWIDTH),
        .NBANKS          (FM_BANK_NUM),
        .HOST_LANES      (AXI_WDATA_DWIDTH / DWIDTH),
        .HOST_GROUP_BITS (2),
        .TOTAL_DWIDTH    (AXI_WDATA_DWIDTH),
        .USE_ASIC_SRAM   (USE_ASIC_SRAM)
    ) u_ping_fmap_memory (
        .CLK                         (CLK),
        .arbiter_FM_wvalid_i         (arbiter_Ping_FM_wvalid_w),
        .arbiter_FM_waddr_i          (arbiter_Ping_FM_waddr_w),
        .arbiter_FM_wdata_i          (arbiter_Ping_FM_wdata_w),
        .arbiter_FM_arvalid_i        (arbiter_Ping_FM_arvalid_w),
        .arbiter_FM_raddr_i          (arbiter_Ping_FM_raddr_w),
        .arbiter_FM_rdata_o          (arbiter_Ping_FM_rdata_w),
        .ctrl_bank_rd_en_i           (ctrl_Ping_FM_bank_rd_en_w),
        .ctrl_bank_wr_en_i           (ctrl_Ping_FM_bank_wr_en_w),
        .ctrl_bank_addr_i            (ctrl_Ping_FM_bank_addr_w),
        .bank_mem_ofmap_i            (bank_mem_ofmap_w),
        .bank_mem_ofmap_valid_i      (bank_mem_ofmap_valid_w),
        .bank_mem_ifmap_o            (ping_ifmap_vector_w),
        .bank_mem_ifmap_valid_o      (ping_ifmap_valid_w)
    );

    Ping_Pong_FMAP_Bank_Memory #(
        .AWIDTH          (AWIDTH),
        .MEM_AWIDTH      (FM_AWIDTH),
        .DWIDTH          (DWIDTH),
        .NBANKS          (FM_BANK_NUM),
        .HOST_LANES      (AXI_WDATA_DWIDTH / DWIDTH),
        .HOST_GROUP_BITS (2),
        .TOTAL_DWIDTH    (AXI_WDATA_DWIDTH),
        .USE_ASIC_SRAM   (USE_ASIC_SRAM)
    ) u_pong_fmap_memory (
        .CLK                         (CLK),
        .arbiter_FM_wvalid_i         (arbiter_Pong_FM_wvalid_w),
        .arbiter_FM_waddr_i          (arbiter_Pong_FM_waddr_w),
        .arbiter_FM_wdata_i          (arbiter_Pong_FM_wdata_w),
        .arbiter_FM_arvalid_i        (arbiter_Pong_FM_arvalid_w),
        .arbiter_FM_raddr_i          (arbiter_Pong_FM_raddr_w),
        .arbiter_FM_rdata_o          (arbiter_Pong_FM_rdata_w),
        .ctrl_bank_rd_en_i           (ctrl_Pong_FM_bank_rd_en_w),
        .ctrl_bank_wr_en_i           (ctrl_Pong_FM_bank_wr_en_w),
        .ctrl_bank_addr_i            (ctrl_Pong_FM_bank_addr_w),
        .bank_mem_ofmap_i            (bank_mem_ofmap_w),
        .bank_mem_ofmap_valid_i      (bank_mem_ofmap_valid_w),
        .bank_mem_ifmap_o            (pong_ifmap_vector_w),
        .bank_mem_ifmap_valid_o      (pong_ifmap_valid_w)
    );

    //-------------------------------------//
    //       Rotator and Line Buffer       //
    //-------------------------------------//
    assign physical_ifmap_vector_w = ping_ifmap_vector_w | pong_ifmap_vector_w;

    IFM_Arbiter #(
        .DWIDTH          (DWIDTH),
        .FM_BANK_NUM     (FM_BANK_NUM),
        .BANK_SEL_DWIDTH (BANK_SEL_DWIDTH)
    ) u_ifm_arbiter (
        .CLK                  (CLK),
        .RST                  (RST),
        .bank_mem_ifmap_i     (physical_ifmap_vector_w),
        .fetch_i              (ifm_fetch_w),
        .ifm_lane_valid_i     (ifm_lane_valid_w),
        .ifm_bank_offset_i    (ifm_bank_offset_w),
        .ifm_vector_o         (rotated_ifmap_vector_w),
        .ifm_valid_o          (rotated_ifmap_valid_w)
    );

    Line_Buffer #(
        .DWIDTH       (DWIDTH),
        .COL_PE_NUM   (COL_PE_NUM),
        .LINE_REG_NUM (COL_PE_NUM-1)
    ) u_line_buffer (
        .CLK             (CLK),
        .RST             (RST),
        .clear_i         (line_buffer_clear_w),
        .load_first_i    (line_buffer_load_first_w && rotated_ifmap_valid_w),
        .load_second_i   (line_buffer_load_second_w && rotated_ifmap_valid_w),
        .shift_i         (line_buffer_shift_w),
        .ifm_vector_i    (rotated_ifmap_vector_w),
        .ifmap_vector_o  (ifmap_vector_w)
    );

    //-------------------------------------//
    //                 PEA                 //
    //-------------------------------------//
    PEA #(
        .DATA_DWIDTH      (DWIDTH),
        .ACC_DWIDTH       (ACC_DWIDTH),
        .SHIFT_DWIDTH     (SHIFT_DWIDTH),
        .COL_PE_NUM       (COL_PE_NUM),
        .ROW_PE_NUM       (ROW_PE_NUM),
        .FM_BANK_NUM      (FM_BANK_NUM),
        .BANK_SEL_DWIDTH  (BANK_SEL_DWIDTH)
    ) u_pea (
        .CLK                       (CLK),
        .RST                       (RST),
        .first_ifmap_i             (first_ifmap_w),
        .last_ifmap_i              (last_ifmap_w),
        .execute_i                 (execute_w),
        .lane_enable_i             (pea_lane_enable_w),
        .row_enable_i              (pea_row_enable_w),
        .output_shift_i            (output_shift_w),
        .ofmap_bank_offset_i       (ofmap_bank_offset_w),
        .ifmap_vector_i            (ifmap_vector_w),
        .row0_mem_weight_i         (bank0_mem_weight_w),
        .row0_mem_weight_valid_i   (bank0_mem_weight_valid_w),
        .row1_mem_weight_i         (bank1_mem_weight_w),
        .row1_mem_weight_valid_i   (bank1_mem_weight_valid_w),
        .row2_mem_weight_i         (bank2_mem_weight_w),
        .row2_mem_weight_valid_i   (bank2_mem_weight_valid_w),
        .row3_mem_weight_i         (bank3_mem_weight_w),
        .row3_mem_weight_valid_i   (bank3_mem_weight_valid_w),
        .row0_mem_bias_i           (bank0_mem_bias_w),
        .row0_mem_bias_valid_i     (bank0_mem_bias_valid_w),
        .row1_mem_bias_i           (bank1_mem_bias_w),
        .row1_mem_bias_valid_i     (bank1_mem_bias_valid_w),
        .row2_mem_bias_i           (bank2_mem_bias_w),
        .row2_mem_bias_valid_i     (bank2_mem_bias_valid_w),
        .row3_mem_bias_i           (bank3_mem_bias_w),
        .row3_mem_bias_valid_i     (bank3_mem_bias_valid_w),
        .bank_mem_ofmap_o          (bank_mem_ofmap_w),
        .bank_mem_ofmap_valid_o    (bank_mem_ofmap_valid_w)
    );

endmodule

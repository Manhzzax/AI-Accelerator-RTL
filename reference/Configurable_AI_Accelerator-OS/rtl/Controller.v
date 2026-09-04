`timescale 1 ns / 1 ps

module Controller #(
    parameter AWIDTH           = 12,
    parameter DWIDTH           = 16,
    parameter INST_DWIDTH      = 64,
    parameter AXI_WDATA_DWIDTH = 64,
    parameter EXEC_DEPTH       = 16,
    parameter COL_PE_NUM       = 16,
    parameter ROW_PE_NUM       = 4,
    parameter FM_BANK_NUM      = 16,
    parameter BANK_SEL_DWIDTH  = 4,
    parameter SHIFT_DWIDTH     = 6
)(
    input  wire                                  CLK,
    input  wire                                  RST,

    //================================//
    //          From Arbiter          //
    //================================//
    input  wire                                  load_flag_i,
    input  wire                                  start_flag_i,
    input  wire                                  done_flag_i,
    input  wire [15:0]                           network_input_width_i,
    input  wire [AWIDTH-1:0]                     max_IM_addr_i,
    output wire [2:0]                            state_o,
    output wire                                  complete_o,

    //================================//
    //        To Weight Memory        //
    //================================//
    output wire                                  ctrl_WM_bank0_rd_en_o,
    output wire                                  ctrl_WM_bank1_rd_en_o,
    output wire                                  ctrl_WM_bank2_rd_en_o,
    output wire                                  ctrl_WM_bank3_rd_en_o,
    output wire [AWIDTH-1:0]                     ctrl_WM_bank0_addr_o,
    output wire [AWIDTH-1:0]                     ctrl_WM_bank1_addr_o,
    output wire [AWIDTH-1:0]                     ctrl_WM_bank2_addr_o,
    output wire [AWIDTH-1:0]                     ctrl_WM_bank3_addr_o,

    //================================//
    //         To Bias Memory         //
    //================================//
    output wire                                  ctrl_BM_bank0_rd_en_o,
    output wire                                  ctrl_BM_bank1_rd_en_o,
    output wire                                  ctrl_BM_bank2_rd_en_o,
    output wire                                  ctrl_BM_bank3_rd_en_o,
    output wire [AWIDTH-1:0]                     ctrl_BM_bank0_addr_o,
    output wire [AWIDTH-1:0]                     ctrl_BM_bank1_addr_o,
    output wire [AWIDTH-1:0]                     ctrl_BM_bank2_addr_o,
    output wire [AWIDTH-1:0]                     ctrl_BM_bank3_addr_o,

    //================================//
    //      To Instruction Memory     //
    //================================//
    output wire                                  ctrl_IM_rd_en_o,
    output wire [AWIDTH-1:0]                     ctrl_IM_addr_o,

    //================================//
    //    From Instruction Memory     //
    //================================//
    input  wire [INST_DWIDTH-1:0]                instruction_i,
    input  wire                                  instruction_valid_i,

    //================================//
    //        To Ping FM Memory       //
    //================================//
    output wire [FM_BANK_NUM-1:0]                ctrl_Ping_FM_bank_rd_en_o,
    output wire [FM_BANK_NUM-1:0]                ctrl_Ping_FM_bank_wr_en_o,
    output wire [(FM_BANK_NUM*AWIDTH)-1:0]       ctrl_Ping_FM_bank_addr_o,

    //================================//
    //        To Pong FM Memory       //
    //================================//
    output wire [FM_BANK_NUM-1:0]                ctrl_Pong_FM_bank_rd_en_o,
    output wire [FM_BANK_NUM-1:0]                ctrl_Pong_FM_bank_wr_en_o,
    output wire [(FM_BANK_NUM*AWIDTH)-1:0]       ctrl_Pong_FM_bank_addr_o,

    //================================//
    //         To IFM Rotator         //
    //================================//
    output wire                                  ifm_fetch_o,
    output reg  [FM_BANK_NUM-1:0]                ifm_lane_valid_o,
    output reg  [BANK_SEL_DWIDTH-1:0]            ifm_bank_offset_o,

    //================================//
    //            From PEA            //
    //================================//
    input  wire [FM_BANK_NUM-1:0]                bank_mem_ofmap_valid_i,

    //================================//
    //             To PEA             //
    //================================//
    output reg                                   first_ifmap_o,
    output reg                                   last_ifmap_o,
    output reg                                   execute_o,
    output reg  [COL_PE_NUM-1:0]                 pea_lane_enable_o,
    output reg  [ROW_PE_NUM-1:0]                 pea_row_enable_o,
    output reg  [SHIFT_DWIDTH-1:0]               output_shift_o,
    output reg  [BANK_SEL_DWIDTH-1:0]            ofmap_bank_offset_o,

    //================================//
    //        To Sliding Buffer       //
    //================================//
    output reg                                   line_buffer_clear_o,
    output reg                                   line_buffer_load_first_o,
    output reg                                   line_buffer_load_second_o,
    output reg                                   line_buffer_shift_o
);

    //================================//
    //            Localparams         //
    //================================//
    localparam [2:0] s_IDLE   = 3'd0;
    localparam [2:0] s_LOAD   = 3'd1;
    localparam [2:0] s_FETCH  = 3'd2;
    localparam [2:0] s_DECODE = 3'd3;
    localparam [2:0] s_EXEC   = 3'd4;
    localparam [2:0] s_READ   = 3'd5;

    localparam [2:0] e_CLEAR  = 3'd0;
    localparam [2:0] e_FETCH0 = 3'd1;
    localparam [2:0] e_EXEC0  = 3'd2;
    localparam [2:0] e_EXEC1  = 3'd3;
    localparam [2:0] e_SHIFT  = 3'd4;
    localparam [2:0] e_OUTPUT = 3'd5;

    localparam [1:0] CONV_STANDARD  = 2'b00;
    localparam [1:0] CONV_DEPTHWISE = 2'b01;

    //-------------------------------------//
    //              Functions              //
    //-------------------------------------//
    function [15:0] calc_out_width;
        input [15:0] in_width_i;
        input [3:0]  kernel_i;
        input [1:0]  stride_mode_i;
        input [3:0]  pad_i;
        reg [31:0] numerator_r;
        begin
            if (({16'd0, in_width_i} + ({28'd0, pad_i} << 1)) <
                {28'd0, kernel_i}) begin
                calc_out_width = 16'd0;
            end
            else begin
                numerator_r = {16'd0, in_width_i} +
                              ({28'd0, pad_i} << 1) -
                              {28'd0, kernel_i};

                case (stride_mode_i)
                    2'b00: calc_out_width = numerator_r[15:0] + 1'b1;
                    default: calc_out_width = 16'd0;
                endcase
            end
        end
    endfunction

    function [COL_PE_NUM-1:0] make_lane_mask;
        input [16:0] valid_count_i;
        integer lane_idx_r;
        begin
            make_lane_mask = {COL_PE_NUM{1'b0}};
            for (lane_idx_r = 0;
                 lane_idx_r < COL_PE_NUM;
                 lane_idx_r = lane_idx_r + 1) begin
                if (lane_idx_r < valid_count_i) begin
                    make_lane_mask[lane_idx_r] = 1'b1;
                end
            end
        end
    endfunction

    function [ROW_PE_NUM-1:0] make_row_mask;
        input [12:0] valid_count_i;
        integer row_idx_r;
        begin
            make_row_mask = {ROW_PE_NUM{1'b0}};
            for (row_idx_r = 0;
                 row_idx_r < ROW_PE_NUM;
                 row_idx_r = row_idx_r + 1) begin
                if (row_idx_r < valid_count_i) begin
                    make_row_mask[row_idx_r] = 1'b1;
                end
            end
        end
    endfunction

    function [ROW_PE_NUM-1:0] make_depthwise_row_mask;
        input [1:0] row_select_i;
        begin
            make_depthwise_row_mask = {ROW_PE_NUM{1'b0}};
            case (row_select_i)
                2'd0: make_depthwise_row_mask[0] = 1'b1;
                2'd1: make_depthwise_row_mask[1] = 1'b1;
                2'd2: make_depthwise_row_mask[2] = 1'b1;
                2'd3: make_depthwise_row_mask[3] = 1'b1;
                default: make_depthwise_row_mask = {ROW_PE_NUM{1'b0}};
            endcase
        end
    endfunction

    //-------------------------------------//
    //         Register Declarations       //
    //-------------------------------------//
    reg [2:0]                              current_state_r;
    reg [2:0]                              next_state_r;
    reg [2:0]                              exec_phase_r;

    reg [AWIDTH:0]                         ctrl_IM_addr_r;

    reg [15:0]                             INPUT_WIDTH_r;
    reg [11:0]                             IN_CH_r;
    reg [11:0]                             OUT_CH_r;
    reg [1:0]                              CONV_MODE_r;
    reg [3:0]                              KERNEL_r;
    reg [3:0]                              PAD_r;
    reg [15:0]                             OUTPUT_WIDTH_r;
    reg [SHIFT_DWIDTH-1:0]                 OUTPUT_SHIFT_r;
    reg [AWIDTH-1:0]                       INPUT_BLOCKS_r;
    reg [AWIDTH-1:0]                       OUTPUT_BLOCKS_r;
    reg [AWIDTH-1:0]                       SRC_FM_BASE_r;
    reg                                    SRC_FM_SEL_r;
    reg                                    DST_FM_SEL_r;

    reg [11:0]                             IN_CH_counter_r;
    reg [11:0]                             OUT_CH_counter_r;
    reg [3:0]                              KERNEL_counter_r;
    reg [15:0]                             OUTPUT_WIDTH_counter_r;
    reg [1:0]                              OFMAP_row_counter_r;
    reg                                    layer_done_r;

    // Persistent sequential weight/bias allocation pointers.
    reg [AWIDTH-1:0]                       weight_layer_base_r;
    reg [AWIDTH-1:0]                       bias_layer_base_r;

    // Per-layer running address bases. These are advanced only by additions.
    reg [AWIDTH-1:0]                       ifm_channel_base_addr_r;
    reg [AWIDTH-1:0]                       weight_group_base_addr_r;
    reg [AWIDTH-1:0]                       weight_in_ch_base_addr_r;
    reg [AWIDTH-1:0]                       ofmap_group_base_addr_r;

    reg [(FM_BANK_NUM*AWIDTH)-1:0]         IFM_phys_bank_addr_r;
    reg [AWIDTH-1:0]                       ofmap_row_offset_r;

    reg                                    weight_req_r;
    reg [3:0]                              weight_req_kernel_r;

    reg signed [17:0]                      ifm_sample_base_r;
    reg signed [17:0]                      ifm_sample_x_r;

    integer                                lane_idx_r;
    integer                                bank_idx_r;

    //-------------------------------------//
    //          Wire Declarations          //
    //-------------------------------------//
    wire                                   fetch_done_w;
    wire                                   depthwise_mode_w;
    wire                                   kernel_last_w;
    wire                                   in_ch_last_w;
    wire                                   output_tile_last_w;
    wire                                   out_ch_tile_last_w;
    wire                                   ofmap_write_fire_w;
    wire                                   ifm_second_block_w;
    wire                                   issue_kernel0_w;
    wire                                   issue_kernel1_w;
    wire                                   issue_kernel2_w;
    wire                                   issue_kernel_next_w;
    wire                                   issue_execute_w;
    wire [3:0]                             issue_kernel_index_w;

    wire [12:0]                            out_ch_remaining_w;
    wire [16:0]                            output_width_remaining_w;
    wire [2:0]                             valid_row_count_w;
    wire [1:0]                             last_ofmap_row_w;

    wire [15:0]                            decoded_output_width_w;
    wire [15:0]                            decoded_input_blocks_w;
    wire [15:0]                            decoded_output_blocks_w;
    wire [15:0]                            output_tile_index_full_w;
    wire [AWIDTH-1:0]                      output_tile_index_w;

    wire [AWIDTH-1:0]                      ifm_read_addr_w;
    wire [AWIDTH-1:0]                      ifm_read_addr_minus1_w;
    wire [FM_BANK_NUM-1:0]                IFM_phys_bank_rd_en_w;

    wire [AWIDTH-1:0]                      kernel_addr_step_w;
    wire [AWIDTH-1:0]                      weight_req_kernel_ext_w;
    wire [AWIDTH-1:0]                      weight_addr_base_w;
    wire [AWIDTH-1:0]                      weight_addr_w;
    wire [11:0]                            bias_group_offset_full_w;
    wire [AWIDTH-1:0]                      bias_addr_w;
    wire [AWIDTH-1:0]                      ofmap_write_addr_w;
    wire [(FM_BANK_NUM*AWIDTH)-1:0]       OFMAP_phys_bank_addr_w;

    wire                                   ping_ifm_active_w;
    wire                                   pong_ifm_active_w;

    //================================//
    //               FSM              //
    //================================//
    always @(*) begin
        case (current_state_r)
            s_IDLE:   next_state_r = load_flag_i ? s_LOAD : s_IDLE;
            s_LOAD:   next_state_r = start_flag_i ? s_FETCH : s_LOAD;
            s_FETCH:  next_state_r = fetch_done_w ? s_DECODE : s_FETCH;
            s_DECODE: next_state_r = instruction_valid_i ? s_EXEC : s_DECODE;
            s_EXEC: begin
                if (layer_done_r) begin
                    next_state_r = (ctrl_IM_addr_r > {1'b0, max_IM_addr_i}) ?
                                   s_READ : s_FETCH;
                end
                else begin
                    next_state_r = s_EXEC;
                end
            end
            s_READ:   next_state_r = done_flag_i ? s_IDLE : s_READ;
            default:  next_state_r = s_IDLE;
        endcase
    end

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            current_state_r <= s_IDLE;
        end
        else begin
            current_state_r <= next_state_r;
        end
    end

    assign state_o    = current_state_r;
    assign complete_o = (current_state_r == s_READ);

    //================================//
    //          FETCH / DECODE        //
    //================================//
    assign ctrl_IM_rd_en_o = (current_state_r == s_FETCH);
    assign ctrl_IM_addr_o  = ctrl_IM_addr_r[AWIDTH-1:0];
    assign fetch_done_w    = ctrl_IM_rd_en_o;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            ctrl_IM_addr_r <= {(AWIDTH+1){1'b0}};
        end
        else begin
            if (current_state_r == s_IDLE) begin
                ctrl_IM_addr_r <= {(AWIDTH+1){1'b0}};
            end
            else if (current_state_r == s_FETCH) begin
                ctrl_IM_addr_r <= ctrl_IM_addr_r + 1'b1;
            end
        end
    end

    assign decoded_output_width_w = calc_out_width(INPUT_WIDTH_r,
                                                    instruction_i[37:34],
                                                    instruction_i[33:32],
                                                    instruction_i[31:28]);
    assign decoded_input_blocks_w  = (INPUT_WIDTH_r + 16'd15) >>
                                      BANK_SEL_DWIDTH;
    assign decoded_output_blocks_w = (decoded_output_width_w + 16'd15) >>
                                      BANK_SEL_DWIDTH;

    // The initial network width is carried in LOAD control data bits [16:1].
    // Width then propagates automatically from one layer to the next.
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            INPUT_WIDTH_r <= 16'd0;
        end
        else if (start_flag_i) begin
            INPUT_WIDTH_r <= network_input_width_i;
        end
        else if (layer_done_r) begin
            INPUT_WIDTH_r <= OUTPUT_WIDTH_r;
        end
    end

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            IN_CH_r          <= 12'd0;
            OUT_CH_r         <= 12'd0;
            CONV_MODE_r      <= CONV_STANDARD;
            KERNEL_r         <= 4'd0;
            PAD_r            <= 4'd0;
            OUTPUT_WIDTH_r   <= 16'd0;
            OUTPUT_SHIFT_r   <= {SHIFT_DWIDTH{1'b0}};
            INPUT_BLOCKS_r   <= {AWIDTH{1'b0}};
            OUTPUT_BLOCKS_r  <= {AWIDTH{1'b0}};
            SRC_FM_BASE_r    <= {AWIDTH{1'b0}};
            SRC_FM_SEL_r     <= 1'b0;
            DST_FM_SEL_r     <= 1'b1;
        end
        else if ((current_state_r == s_DECODE) && instruction_valid_i) begin
            CONV_MODE_r      <= instruction_i[59:58];
            IN_CH_r          <= {2'b00, instruction_i[57:48]};
            OUT_CH_r         <= {2'b00, instruction_i[47:38]};
            KERNEL_r         <= instruction_i[37:34];
            PAD_r            <= instruction_i[31:28];
            OUTPUT_SHIFT_r   <= instruction_i[27:22];
            SRC_FM_BASE_r    <= instruction_i[21:12];
            SRC_FM_SEL_r     <= instruction_i[1];
            DST_FM_SEL_r     <= instruction_i[0];
            OUTPUT_WIDTH_r   <= decoded_output_width_w;
            INPUT_BLOCKS_r   <= decoded_input_blocks_w[AWIDTH-1:0];
            OUTPUT_BLOCKS_r  <= decoded_output_blocks_w[AWIDTH-1:0];
        end
    end

    //================================//
    //        EXECUTION SCHEDULER     //
    //================================//
    assign depthwise_mode_w   = (CONV_MODE_r == CONV_DEPTHWISE);
    assign kernel_last_w      = (KERNEL_counter_r == (KERNEL_r - 1'b1));
    assign in_ch_last_w       = depthwise_mode_w ? 1'b1 :
                                (IN_CH_counter_r == (IN_CH_r - 1'b1));
    assign output_tile_last_w = ((OUTPUT_WIDTH_counter_r + COL_PE_NUM) >=
                                 OUTPUT_WIDTH_r);
    assign out_ch_tile_last_w = depthwise_mode_w ?
                                ((OUT_CH_counter_r + 1'b1) >= OUT_CH_r) :
                                ((OUT_CH_counter_r + ROW_PE_NUM) >= OUT_CH_r);

    assign out_ch_remaining_w       = {1'b0, OUT_CH_r} -
                                      {1'b0, OUT_CH_counter_r};
    assign output_width_remaining_w = {1'b0, OUTPUT_WIDTH_r} -
                                      {1'b0, OUTPUT_WIDTH_counter_r};
    assign valid_row_count_w        = depthwise_mode_w ? 3'd1 :
                                      ((out_ch_remaining_w >= ROW_PE_NUM) ?
                                       ROW_PE_NUM[2:0] :
                                       out_ch_remaining_w[2:0]);
    assign last_ofmap_row_w         = valid_row_count_w[1:0] - 1'b1;
    assign ofmap_write_fire_w       = |bank_mem_ofmap_valid_i;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            exec_phase_r                <= e_CLEAR;
            IN_CH_counter_r             <= 12'd0;
            OUT_CH_counter_r            <= 12'd0;
            KERNEL_counter_r            <= 4'd0;
            OUTPUT_WIDTH_counter_r      <= 16'd0;
            OFMAP_row_counter_r         <= 2'd0;
            layer_done_r                <= 1'b0;
            weight_layer_base_r         <= {AWIDTH{1'b0}};
            bias_layer_base_r           <= {AWIDTH{1'b0}};
            ifm_channel_base_addr_r     <= {AWIDTH{1'b0}};
            weight_group_base_addr_r    <= {AWIDTH{1'b0}};
            weight_in_ch_base_addr_r    <= {AWIDTH{1'b0}};
            ofmap_group_base_addr_r     <= {AWIDTH{1'b0}};
        end
        else begin
            layer_done_r <= 1'b0;

            if (current_state_r == s_IDLE) begin
                exec_phase_r                <= e_CLEAR;
                IN_CH_counter_r             <= 12'd0;
                OUT_CH_counter_r            <= 12'd0;
                KERNEL_counter_r            <= 4'd0;
                OUTPUT_WIDTH_counter_r      <= 16'd0;
                OFMAP_row_counter_r         <= 2'd0;
                weight_layer_base_r         <= {AWIDTH{1'b0}};
                bias_layer_base_r           <= {AWIDTH{1'b0}};
                ifm_channel_base_addr_r     <= {AWIDTH{1'b0}};
                weight_group_base_addr_r    <= {AWIDTH{1'b0}};
                weight_in_ch_base_addr_r    <= {AWIDTH{1'b0}};
                ofmap_group_base_addr_r     <= {AWIDTH{1'b0}};
            end
            else if ((current_state_r == s_DECODE) && instruction_valid_i) begin
                exec_phase_r                <= e_CLEAR;
                IN_CH_counter_r             <= 12'd0;
                OUT_CH_counter_r            <= 12'd0;
                KERNEL_counter_r            <= 4'd0;
                OUTPUT_WIDTH_counter_r      <= 16'd0;
                OFMAP_row_counter_r         <= 2'd0;
                ifm_channel_base_addr_r     <= instruction_i[21:12];
                weight_group_base_addr_r    <= weight_layer_base_r;
                weight_in_ch_base_addr_r    <= weight_layer_base_r;
                ofmap_group_base_addr_r     <= instruction_i[11:2];
            end
            else if (current_state_r != s_EXEC) begin
                exec_phase_r           <= e_CLEAR;
                KERNEL_counter_r       <= 4'd0;
                OFMAP_row_counter_r    <= 2'd0;
            end
            else begin
                case (exec_phase_r)
                    e_CLEAR: begin
                        KERNEL_counter_r <= 4'd0;
                        exec_phase_r     <= e_FETCH0;
                    end

                    e_FETCH0: begin
                        KERNEL_counter_r <= 4'd0;
                        exec_phase_r     <= e_EXEC0;
                    end

                    e_EXEC0: begin
                        if (KERNEL_r == 4'd1) begin
                            if (in_ch_last_w) begin
                                OFMAP_row_counter_r <= 2'd0;
                                exec_phase_r        <= e_OUTPUT;
                            end
                            else begin
                                IN_CH_counter_r          <= IN_CH_counter_r + 1'b1;
                                ifm_channel_base_addr_r  <= ifm_channel_base_addr_r +
                                                            INPUT_BLOCKS_r;
                                weight_in_ch_base_addr_r <= weight_in_ch_base_addr_r +
                                                            kernel_addr_step_w;
                                exec_phase_r             <= e_CLEAR;
                            end
                        end
                        else begin
                            KERNEL_counter_r <= 4'd1;
                            exec_phase_r     <= e_EXEC1;
                        end
                    end

                    e_EXEC1: begin
                        if (KERNEL_r == 4'd2) begin
                            if (in_ch_last_w) begin
                                OFMAP_row_counter_r <= 2'd0;
                                exec_phase_r        <= e_OUTPUT;
                            end
                            else begin
                                IN_CH_counter_r          <= IN_CH_counter_r + 1'b1;
                                ifm_channel_base_addr_r  <= ifm_channel_base_addr_r +
                                                            INPUT_BLOCKS_r;
                                weight_in_ch_base_addr_r <= weight_in_ch_base_addr_r +
                                                            kernel_addr_step_w;
                                exec_phase_r             <= e_CLEAR;
                            end
                        end
                        else begin
                            KERNEL_counter_r <= 4'd2;
                            exec_phase_r     <= e_SHIFT;
                        end
                    end

                    e_SHIFT: begin
                        if (kernel_last_w) begin
                            if (in_ch_last_w) begin
                                OFMAP_row_counter_r <= 2'd0;
                                exec_phase_r        <= e_OUTPUT;
                            end
                            else begin
                                IN_CH_counter_r          <= IN_CH_counter_r + 1'b1;
                                ifm_channel_base_addr_r  <= ifm_channel_base_addr_r +
                                                            INPUT_BLOCKS_r;
                                weight_in_ch_base_addr_r <= weight_in_ch_base_addr_r +
                                                            kernel_addr_step_w;
                                exec_phase_r             <= e_CLEAR;
                            end
                        end
                        else begin
                            KERNEL_counter_r <= KERNEL_counter_r + 1'b1;
                        end
                    end

                    e_OUTPUT: begin
                        if (ofmap_write_fire_w) begin
                            if (OFMAP_row_counter_r == last_ofmap_row_w) begin
                                OFMAP_row_counter_r <= 2'd0;
                                IN_CH_counter_r     <= 12'd0;

                                if (output_tile_last_w) begin
                                    OUTPUT_WIDTH_counter_r <= 16'd0;

                                    if (out_ch_tile_last_w) begin
                                        OUT_CH_counter_r <= 12'd0;

                                        if (depthwise_mode_w) begin
                                            weight_layer_base_r <=
                                                weight_group_base_addr_r +
                                                kernel_addr_step_w;
                                        end
                                        else begin
                                            weight_layer_base_r <=
                                                weight_in_ch_base_addr_r +
                                                kernel_addr_step_w;
                                        end

                                        bias_layer_base_r <= bias_addr_w + 1'b1;
                                        layer_done_r      <= 1'b1;
                                        exec_phase_r      <= e_OUTPUT;
                                    end
                                    else if (depthwise_mode_w) begin
                                        OUT_CH_counter_r <= OUT_CH_counter_r + 1'b1;
                                        ifm_channel_base_addr_r <=
                                            ifm_channel_base_addr_r + INPUT_BLOCKS_r;
                                        ofmap_group_base_addr_r <=
                                            ofmap_group_base_addr_r + OUTPUT_BLOCKS_r;

                                        if (OUT_CH_counter_r[1:0] == 2'd3) begin
                                            weight_group_base_addr_r <=
                                                weight_group_base_addr_r +
                                                kernel_addr_step_w;
                                            weight_in_ch_base_addr_r <=
                                                weight_group_base_addr_r +
                                                kernel_addr_step_w;
                                        end
                                        else begin
                                            weight_in_ch_base_addr_r <=
                                                weight_group_base_addr_r;
                                        end

                                        exec_phase_r <= e_CLEAR;
                                    end
                                    else begin
                                        OUT_CH_counter_r         <= OUT_CH_counter_r +
                                                                    ROW_PE_NUM;
                                        ifm_channel_base_addr_r  <= SRC_FM_BASE_r;
                                        weight_group_base_addr_r <=
                                            weight_in_ch_base_addr_r +
                                            kernel_addr_step_w;
                                        weight_in_ch_base_addr_r <=
                                            weight_in_ch_base_addr_r +
                                            kernel_addr_step_w;
                                        ofmap_group_base_addr_r  <=
                                            ofmap_group_base_addr_r +
                                            (OUTPUT_BLOCKS_r << 2);
                                        exec_phase_r <= e_CLEAR;
                                    end
                                end
                                else begin
                                    OUTPUT_WIDTH_counter_r <= OUTPUT_WIDTH_counter_r +
                                                              COL_PE_NUM;

                                    if (!depthwise_mode_w) begin
                                        ifm_channel_base_addr_r  <= SRC_FM_BASE_r;
                                        weight_in_ch_base_addr_r <=
                                            weight_group_base_addr_r;
                                    end
                                    else begin
                                        weight_in_ch_base_addr_r <=
                                            weight_group_base_addr_r;
                                    end

                                    exec_phase_r <= e_CLEAR;
                                end
                            end
                            else begin
                                OFMAP_row_counter_r <= OFMAP_row_counter_r + 1'b1;
                            end
                        end
                    end

                    default: exec_phase_r <= e_CLEAR;
                endcase
            end
        end
    end

    //================================//
    //         PEA / Buffer Control   //
    //================================//
    assign issue_kernel0_w = (current_state_r == s_EXEC) &&
                             (exec_phase_r == e_FETCH0);

    assign issue_kernel1_w = (current_state_r == s_EXEC) &&
                             (exec_phase_r == e_EXEC0) &&
                             (KERNEL_r > 4'd1);

    assign issue_kernel2_w = (current_state_r == s_EXEC) &&
                             (exec_phase_r == e_EXEC1) &&
                             (KERNEL_r > 4'd2);

    assign issue_kernel_next_w = (current_state_r == s_EXEC) &&
                                 (exec_phase_r == e_SHIFT) &&
                                 !kernel_last_w;

    assign issue_execute_w = issue_kernel0_w ||
                             issue_kernel1_w ||
                             issue_kernel2_w ||
                             issue_kernel_next_w;

    assign issue_kernel_index_w = issue_kernel0_w ? 4'd0 :
                                  issue_kernel1_w ? 4'd1 :
                                  issue_kernel2_w ? 4'd2 :
                                  issue_kernel_next_w ?
                                      (KERNEL_counter_r + 1'b1) :
                                      4'd0;

    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            first_ifmap_o              <= 1'b0;
            last_ifmap_o               <= 1'b0;
            execute_o                  <= 1'b0;
            pea_lane_enable_o          <= {COL_PE_NUM{1'b0}};
            pea_row_enable_o           <= {ROW_PE_NUM{1'b0}};
            output_shift_o             <= {SHIFT_DWIDTH{1'b0}};
            ofmap_bank_offset_o        <= {BANK_SEL_DWIDTH{1'b0}};
            line_buffer_clear_o        <= 1'b0;
            line_buffer_load_first_o   <= 1'b0;
            line_buffer_load_second_o  <= 1'b0;
            line_buffer_shift_o        <= 1'b0;
        end
        else begin
            execute_o                 <= issue_execute_w;
            first_ifmap_o             <= issue_execute_w &&
                                         (issue_kernel_index_w == 4'd0) &&
                                         (depthwise_mode_w ||
                                          (IN_CH_counter_r == 12'd0));
            last_ifmap_o              <= issue_execute_w &&
                                         (issue_kernel_index_w ==
                                          (KERNEL_r - 1'b1)) &&
                                         (depthwise_mode_w || in_ch_last_w);
            pea_lane_enable_o         <= make_lane_mask(output_width_remaining_w);
            pea_row_enable_o          <= depthwise_mode_w ?
                                         make_depthwise_row_mask(
                                             OUT_CH_counter_r[1:0]) :
                                         make_row_mask(out_ch_remaining_w);
            output_shift_o            <= OUTPUT_SHIFT_r;
            ofmap_bank_offset_o       <= {BANK_SEL_DWIDTH{1'b0}};

            line_buffer_clear_o       <= (current_state_r == s_EXEC) &&
                                         (exec_phase_r == e_CLEAR);
            line_buffer_load_first_o  <= issue_kernel0_w;
            line_buffer_load_second_o <= issue_kernel1_w;
            line_buffer_shift_o       <= issue_kernel2_w ||
                                         issue_kernel_next_w;
        end
    end

    //================================//
    //         Weight / Bias Reads    //
    //================================//
    always @(*) begin
        weight_req_r        = 1'b0;
        weight_req_kernel_r = 4'd0;

        if (current_state_r == s_EXEC) begin
            case (exec_phase_r)
                e_FETCH0: begin
                    weight_req_r        = 1'b1;
                    weight_req_kernel_r = 4'd0;
                end
                e_EXEC0: begin
                    if (KERNEL_r > 4'd1) begin
                        weight_req_r        = 1'b1;
                        weight_req_kernel_r = 4'd1;
                    end
                end
                e_EXEC1: begin
                    if (KERNEL_r > 4'd2) begin
                        weight_req_r        = 1'b1;
                        weight_req_kernel_r = 4'd2;
                    end
                end
                e_SHIFT: begin
                    if (!kernel_last_w) begin
                        weight_req_r        = 1'b1;
                        weight_req_kernel_r = KERNEL_counter_r + 1'b1;
                    end
                end
                default: begin
                    weight_req_r        = 1'b0;
                    weight_req_kernel_r = 4'd0;
                end
            endcase
        end
    end

    assign kernel_addr_step_w      = {{(AWIDTH-4){1'b0}}, KERNEL_r};
    assign weight_req_kernel_ext_w = {{(AWIDTH-4){1'b0}},
                                       weight_req_kernel_r};
    assign weight_addr_base_w      = depthwise_mode_w ?
                                      weight_group_base_addr_r :
                                      weight_in_ch_base_addr_r;
    assign weight_addr_w           = weight_addr_base_w +
                                      weight_req_kernel_ext_w;
    assign bias_group_offset_full_w = OUT_CH_counter_r >> 2;
    assign bias_addr_w              = bias_layer_base_r +
                                      bias_group_offset_full_w[AWIDTH-1:0];

    assign ctrl_WM_bank0_rd_en_o = weight_req_r;
    assign ctrl_WM_bank1_rd_en_o = weight_req_r;
    assign ctrl_WM_bank2_rd_en_o = weight_req_r;
    assign ctrl_WM_bank3_rd_en_o = weight_req_r;

    assign ctrl_WM_bank0_addr_o = weight_addr_w;
    assign ctrl_WM_bank1_addr_o = weight_addr_w;
    assign ctrl_WM_bank2_addr_o = weight_addr_w;
    assign ctrl_WM_bank3_addr_o = weight_addr_w;

    assign ctrl_BM_bank0_rd_en_o = (current_state_r == s_EXEC) &&
                                    (exec_phase_r == e_FETCH0);
    assign ctrl_BM_bank1_rd_en_o = ctrl_BM_bank0_rd_en_o;
    assign ctrl_BM_bank2_rd_en_o = ctrl_BM_bank0_rd_en_o;
    assign ctrl_BM_bank3_rd_en_o = ctrl_BM_bank0_rd_en_o;

    assign ctrl_BM_bank0_addr_o = bias_addr_w;
    assign ctrl_BM_bank1_addr_o = bias_addr_w;
    assign ctrl_BM_bank2_addr_o = bias_addr_w;
    assign ctrl_BM_bank3_addr_o = bias_addr_w;

    //================================//
    //        Two 16-Wide IFM Reads   //
    //================================//
    assign ifm_fetch_o = (current_state_r == s_EXEC) &&
                         ((exec_phase_r == e_FETCH0) ||
                          ((exec_phase_r == e_EXEC0) && (KERNEL_r > 4'd1)));

    assign ifm_second_block_w = (exec_phase_r == e_EXEC0) &&
                                (KERNEL_r > 4'd1);

    assign output_tile_index_full_w = OUTPUT_WIDTH_counter_r >>
                                      BANK_SEL_DWIDTH;
    assign output_tile_index_w      = output_tile_index_full_w[AWIDTH-1:0];

    assign ifm_read_addr_w = ifm_channel_base_addr_r +
                             output_tile_index_w +
                             ifm_second_block_w;

    assign ifm_read_addr_minus1_w = (ifm_read_addr_w == {AWIDTH{1'b0}}) ?
                                     {AWIDTH{1'b0}} :
                                     (ifm_read_addr_w - 1'b1);

    assign IFM_phys_bank_rd_en_w = ifm_fetch_o ?
                                    {FM_BANK_NUM{1'b1}} :
                                    {FM_BANK_NUM{1'b0}};

    always @(*) begin
        if (PAD_r == 4'd0) begin
            ifm_bank_offset_o = {BANK_SEL_DWIDTH{1'b0}};
        end
        else begin
            ifm_bank_offset_o = (~PAD_r) + 1'b1;
        end

        ifm_lane_valid_o  = {FM_BANK_NUM{1'b0}};
        ifm_sample_base_r = $signed({2'b00, OUTPUT_WIDTH_counter_r}) -
                            $signed({14'd0, PAD_r});
        ifm_sample_x_r    = 18'sd0;

        if (ifm_second_block_w) begin
            ifm_sample_base_r = ifm_sample_base_r + 18'sd16;
        end

        if (ifm_fetch_o) begin
            for (lane_idx_r = 0;
                 lane_idx_r < FM_BANK_NUM;
                 lane_idx_r = lane_idx_r + 1) begin
                ifm_sample_x_r = ifm_sample_base_r +
                                     $signed(lane_idx_r[17:0]);

                if ((ifm_sample_x_r >= 0) &&
                    (ifm_sample_x_r < $signed({2'b00, INPUT_WIDTH_r}))) begin
                    ifm_lane_valid_o[lane_idx_r] = 1'b1;
                end
            end
        end
    end

    always @(*) begin
        IFM_phys_bank_addr_r = {(FM_BANK_NUM*AWIDTH){1'b0}};

        for (bank_idx_r = 0;
             bank_idx_r < FM_BANK_NUM;
             bank_idx_r = bank_idx_r + 1) begin
            if ((ifm_bank_offset_o != {BANK_SEL_DWIDTH{1'b0}}) &&
                (bank_idx_r >= ifm_bank_offset_o)) begin
                IFM_phys_bank_addr_r[(bank_idx_r*AWIDTH) +: AWIDTH] =
                    ifm_read_addr_minus1_w;
            end
            else begin
                IFM_phys_bank_addr_r[(bank_idx_r*AWIDTH) +: AWIDTH] =
                    ifm_read_addr_w;
            end
        end
    end

    //================================//
    //          OFMAP Writeback       //
    //================================//
    always @(*) begin
        if (depthwise_mode_w) begin
            ofmap_row_offset_r = {AWIDTH{1'b0}};
        end
        else begin
            case (OFMAP_row_counter_r)
                2'd0: ofmap_row_offset_r = {AWIDTH{1'b0}};
                2'd1: ofmap_row_offset_r = OUTPUT_BLOCKS_r;
                2'd2: ofmap_row_offset_r = OUTPUT_BLOCKS_r << 1;
                2'd3: ofmap_row_offset_r = (OUTPUT_BLOCKS_r << 1) +
                                             OUTPUT_BLOCKS_r;
                default: ofmap_row_offset_r = {AWIDTH{1'b0}};
            endcase
        end
    end

    assign ofmap_write_addr_w = ofmap_group_base_addr_r +
                                ofmap_row_offset_r +
                                output_tile_index_w;

    assign OFMAP_phys_bank_addr_w = {FM_BANK_NUM{ofmap_write_addr_w}};

    assign ping_ifm_active_w   = (SRC_FM_SEL_r == 1'b0) && ifm_fetch_o;
    assign pong_ifm_active_w   = (SRC_FM_SEL_r == 1'b1) && ifm_fetch_o;
    assign ctrl_Ping_FM_bank_rd_en_o = ping_ifm_active_w ?
                                        IFM_phys_bank_rd_en_w :
                                        {FM_BANK_NUM{1'b0}};

    assign ctrl_Pong_FM_bank_rd_en_o = pong_ifm_active_w ?
                                        IFM_phys_bank_rd_en_w :
                                        {FM_BANK_NUM{1'b0}};

    assign ctrl_Ping_FM_bank_wr_en_o =
        ((current_state_r == s_EXEC) && (DST_FM_SEL_r == 1'b0)) ?
        bank_mem_ofmap_valid_i : {FM_BANK_NUM{1'b0}};

    assign ctrl_Pong_FM_bank_wr_en_o =
        ((current_state_r == s_EXEC) && (DST_FM_SEL_r == 1'b1)) ?
        bank_mem_ofmap_valid_i : {FM_BANK_NUM{1'b0}};

    // Read and write phases do not overlap. Therefore the same physical Ping
    // or Pong memory may be selected as both source and destination when the
    // programmed tensor ranges do not overlap.
    assign ctrl_Ping_FM_bank_addr_o = ping_ifm_active_w ?
                                      IFM_phys_bank_addr_r :
                                      OFMAP_phys_bank_addr_w;

    assign ctrl_Pong_FM_bank_addr_o = pong_ifm_active_w ?
                                      IFM_phys_bank_addr_r :
                                      OFMAP_phys_bank_addr_w;

endmodule

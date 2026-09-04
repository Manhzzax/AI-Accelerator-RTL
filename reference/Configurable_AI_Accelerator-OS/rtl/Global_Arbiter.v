`timescale 1 ns / 1 ps

module Global_Arbiter #(
    parameter MAWIDTH            = 12,
    parameter INST_MDWIDTH       = 64,
    parameter AXI_WADDR_WIDTH    = MAWIDTH + 3,
    parameter AXI_RADDR_WIDTH    = MAWIDTH + 3,
    parameter AXI_WDATA_MDWIDTH  = 64,
    parameter AXI_RDATA_MDWIDTH  = 64
)(
    input  wire                             CLK,
    input  wire                             RST,

    //================================//
    //          AXI-Lite Like         //
    //================================//
    input  wire [AXI_WADDR_WIDTH-1:0]       axi_waddr_i,
    input  wire [AXI_WDATA_MDWIDTH-1:0]     axi_wdata_i,
    input  wire                             axi_wvalid_i,

    input  wire [AXI_RADDR_WIDTH-1:0]       axi_raddr_i,
    input  wire                             axi_arvalid_i,
    output reg  [AXI_RDATA_MDWIDTH-1:0]     axi_rdata_o,

    //================================//
    //        Direct Control Path      //
    //================================//
    input  wire                             direct_load_i,
    input  wire                             direct_start_i,
    input  wire                             direct_done_i,

    //================================//
    //         From Controller        //
    //================================//
    input  wire [2:0]                       state_i,
    input  wire                             completed_i,

    //================================//
    //         To Controller          //
    //================================//
    output wire                             load_flag_o,
    output wire                             start_flag_o,
    output wire                             done_flag_o,
    output reg  [15:0]                      network_input_width_o,
    output reg  [MAWIDTH-1:0]               max_IM_addr_o,

    //================================//
    //        To Instruction Mem      //
    //================================//
    output wire                             arbiter_IM_wvalid_o,
    output wire [MAWIDTH-1:0]               arbiter_IM_waddr_o,
    output wire [INST_MDWIDTH-1:0]          arbiter_IM_wdata_o,

    //================================//
    //         To Ping FM Mem         //
    //================================//
    output wire                             arbiter_Ping_FM_wvalid_o,
    output wire [MAWIDTH-1:0]               arbiter_Ping_FM_waddr_o,
    output wire [AXI_WDATA_MDWIDTH-1:0]     arbiter_Ping_FM_wdata_o,

    output wire                             arbiter_Ping_FM_arvalid_o,
    output wire [MAWIDTH-1:0]               arbiter_Ping_FM_raddr_o,
    input  wire [AXI_RDATA_MDWIDTH-1:0]     arbiter_Ping_FM_rdata_i,

    //================================//
    //         To Pong FM Mem         //
    //================================//
    output wire                             arbiter_Pong_FM_wvalid_o,
    output wire [MAWIDTH-1:0]               arbiter_Pong_FM_waddr_o,
    output wire [AXI_WDATA_MDWIDTH-1:0]     arbiter_Pong_FM_wdata_o,

    output wire                             arbiter_Pong_FM_arvalid_o,
    output wire [MAWIDTH-1:0]               arbiter_Pong_FM_raddr_o,
    input  wire [AXI_RDATA_MDWIDTH-1:0]     arbiter_Pong_FM_rdata_i,

    //================================//
    //        To Weight Memory        //
    //================================//
    output wire                             arbiter_WM_wvalid_o,
    output wire [MAWIDTH-1:0]               arbiter_WM_waddr_o,
    output wire [AXI_WDATA_MDWIDTH-1:0]     arbiter_WM_wdata_o,

    //================================//
    //         To Bias Memory         //
    //================================//
    output wire                             arbiter_BM_wvalid_o,
    output wire [MAWIDTH-1:0]               arbiter_BM_waddr_o,
    output wire [AXI_WDATA_MDWIDTH-1:0]     arbiter_BM_wdata_o
);

    //-------------------------------------//
    //            Localparams              //
    //-------------------------------------//
    localparam [2:0] s_IDLE               = 3'd0;
    localparam [2:0] s_LOAD               = 3'd1;
    localparam [2:0] s_FETCH              = 3'd2;
    localparam [2:0] s_DECODE             = 3'd3;
    localparam [2:0] s_EXEC               = 3'd4;
    localparam [2:0] s_READ               = 3'd5;

    localparam [2:0] AXI_WADDR_LOAD       = 3'd0;
    localparam [2:0] AXI_WADDR_START      = 3'd1;
    localparam [2:0] AXI_WADDR_DONE       = 3'd2;
    localparam [2:0] AXI_WADDR_PING_FMAP  = 3'd3;
    localparam [2:0] AXI_WADDR_PONG_FMAP  = 3'd4;
    localparam [2:0] AXI_WADDR_WEIGHT     = 3'd5;
    localparam [2:0] AXI_WADDR_BIAS       = 3'd6;
    localparam [2:0] AXI_WADDR_INST       = 3'd7;

    localparam [2:0] AXI_RADDR_COMPLETE   = 3'd0;
    localparam [2:0] AXI_RADDR_PING_FMAP  = 3'd1;
    localparam [2:0] AXI_RADDR_PONG_FMAP  = 3'd2;
    localparam [2:0] AXI_RADDR_STATE      = 3'd3;

    //-------------------------------------//
    //          Wire Declarations          //
    //-------------------------------------//
    wire [2:0]                            axi_waddr_sel_w;
    wire [2:0]                            axi_raddr_sel_w;
	wire [2:0]                            axi_raddr_sel_delay_w;

    wire                                  axi_load_flag_w;
    wire                                  axi_start_flag_w;
    wire                                  axi_done_flag_w;

    wire                                  load_state_w;
    wire                                  read_state_w;

	reg  [AXI_RADDR_WIDTH-1:0]     			axi_raddr_r;

    //-------------------------------------//
    //               Decode               //
    //-------------------------------------//
    assign axi_waddr_sel_w                = axi_waddr_i[AXI_WADDR_WIDTH-1:MAWIDTH];
    assign axi_raddr_sel_w                = axi_raddr_i[AXI_RADDR_WIDTH-1:MAWIDTH];
	assign axi_raddr_sel_delay_w          = axi_raddr_r[AXI_RADDR_WIDTH-1:MAWIDTH];
 
    assign axi_load_flag_w                = axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_LOAD)  && axi_wdata_i[0];
    assign axi_start_flag_w               = axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_START) && axi_wdata_i[0];
    assign axi_done_flag_w                = axi_wvalid_i && (axi_waddr_sel_w == AXI_WADDR_DONE)  && axi_wdata_i[0];

    assign load_flag_o                    = direct_load_i  | axi_load_flag_w;
    assign start_flag_o                   = direct_start_i | axi_start_flag_w;
    assign done_flag_o                    = direct_done_i  | axi_done_flag_w;

    assign load_state_w                   = (state_i == s_LOAD);
    assign read_state_w                   = (state_i == s_READ);

    //-------------------------------------//
    //         Write Decode Path           //
    //-------------------------------------//
    assign arbiter_BM_wvalid_o            = load_state_w &&
                                            axi_wvalid_i &&
                                            (axi_waddr_sel_w == AXI_WADDR_BIAS);
    assign arbiter_BM_waddr_o             = axi_waddr_i[MAWIDTH-1:0];
    assign arbiter_BM_wdata_o             = axi_wdata_i;

    assign arbiter_WM_wvalid_o            = load_state_w &&
                                            axi_wvalid_i &&
                                            (axi_waddr_sel_w == AXI_WADDR_WEIGHT);
    assign arbiter_WM_waddr_o             = axi_waddr_i[MAWIDTH-1:0];
    assign arbiter_WM_wdata_o             = axi_wdata_i;

    assign arbiter_IM_wvalid_o            = load_state_w &&
                                            axi_wvalid_i &&
                                            (axi_waddr_sel_w == AXI_WADDR_INST);
    assign arbiter_IM_waddr_o             = axi_waddr_i[MAWIDTH-1:0];
    assign arbiter_IM_wdata_o             = axi_wdata_i[INST_MDWIDTH-1:0];

    assign arbiter_Ping_FM_wvalid_o       = load_state_w &&
                                            axi_wvalid_i &&
                                            (axi_waddr_sel_w == AXI_WADDR_PING_FMAP);
    assign arbiter_Ping_FM_waddr_o        = axi_waddr_i[MAWIDTH-1:0];
    assign arbiter_Ping_FM_wdata_o        = axi_wdata_i;

    assign arbiter_Pong_FM_wvalid_o       = load_state_w &&
                                            axi_wvalid_i &&
                                            (axi_waddr_sel_w == AXI_WADDR_PONG_FMAP);
    assign arbiter_Pong_FM_waddr_o        = axi_waddr_i[MAWIDTH-1:0];
    assign arbiter_Pong_FM_wdata_o        = axi_wdata_i;

    //-------------------------------------//
    //           Read Decode Path          //
    //-------------------------------------//
    assign arbiter_Ping_FM_arvalid_o      = read_state_w &&
                                            axi_arvalid_i &&
                                            (axi_raddr_sel_w == AXI_RADDR_PING_FMAP);
    assign arbiter_Ping_FM_raddr_o        = axi_raddr_i[MAWIDTH-1:0];

    assign arbiter_Pong_FM_arvalid_o      = read_state_w &&
                                            axi_arvalid_i &&
                                            (axi_raddr_sel_w == AXI_RADDR_PONG_FMAP);
    assign arbiter_Pong_FM_raddr_o        = axi_raddr_i[MAWIDTH-1:0];

    //-------------------------------------//
    //           Max IM Address            //
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            max_IM_addr_o                  <= {MAWIDTH{1'b0}};
            network_input_width_o           <= 16'd0;
			axi_raddr_r						<= 0;
        end
		else begin
            if (axi_arvalid_i) begin
                axi_raddr_r <= axi_raddr_i;
            end

            if (axi_load_flag_w) begin
                network_input_width_o <= axi_wdata_i[16:1];
            end

			if (arbiter_IM_wvalid_o) begin
				if (arbiter_IM_waddr_o >= max_IM_addr_o) begin
					max_IM_addr_o              <= arbiter_IM_waddr_o;
				end
			end
        end
    end

    //-------------------------------------//
    //             AXI Read                //
    //-------------------------------------//
    always @(*) begin
        case (axi_raddr_sel_delay_w)
            AXI_RADDR_COMPLETE:  axi_rdata_o = {{(AXI_RDATA_MDWIDTH-1){1'b0}}, completed_i};
            AXI_RADDR_PING_FMAP: axi_rdata_o = arbiter_Ping_FM_rdata_i;
            AXI_RADDR_PONG_FMAP: axi_rdata_o = arbiter_Pong_FM_rdata_i;
            AXI_RADDR_STATE:     axi_rdata_o = {{(AXI_RDATA_MDWIDTH-3){1'b0}}, state_i};
            default:             axi_rdata_o = {AXI_RDATA_MDWIDTH{1'b0}};
        endcase
    end

endmodule

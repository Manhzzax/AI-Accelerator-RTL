`timescale 1 ns / 1 ps

module Line_Buffer #(
    parameter DWIDTH        = 16,
    parameter COL_PE_NUM    = 16,
    parameter LINE_REG_NUM  = COL_PE_NUM - 1
)(
    input  wire                                  CLK,
    input  wire                                  RST,

    //================================//
    //             Control            //
    //================================//
    input  wire                                  clear_i,
    input  wire                                  load_first_i,
    input  wire                                  load_second_i,
    input  wire                                  shift_i,

    //================================//
    //       Rotated 16-Lane IFM      //
    //================================//
    input  wire [(COL_PE_NUM*DWIDTH)-1:0]        ifm_vector_i,

    //================================//
    //       Vector to Spatial PEs    //
    //================================//
    output reg  [(COL_PE_NUM*DWIDTH)-1:0]        ifmap_vector_o
);

    //-------------------------------------//
    //         Register Declarations       //
    //-------------------------------------//
    reg [DWIDTH-1:0]                            pe_buffer_r [0:COL_PE_NUM-1];
    reg [DWIDTH-1:0]                            line_buffer_r [0:LINE_REG_NUM-1];

    integer                                     pe_idx_r;
    integer                                     line_idx_r;

    //-------------------------------------//
    //         Current Kernel Vector       //
    //-------------------------------------//
    // k=0: bypass the first memory vector while storing it in pe_buffer_r.
    // k=1: shift pe_buffer_r once, use second_vector[0] for PE15, and store
    //      second_vector[1..15] in the fifteen line-buffer registers.
    // k>=2: shift one sample from line_buffer_r into PE15 each cycle.
    always @(*) begin
        ifmap_vector_o = {(COL_PE_NUM*DWIDTH){1'b0}};

        for (pe_idx_r = 0; pe_idx_r < COL_PE_NUM; pe_idx_r = pe_idx_r + 1) begin
            ifmap_vector_o[(pe_idx_r*DWIDTH) +: DWIDTH] = pe_buffer_r[pe_idx_r];
        end

        if (load_first_i) begin
            ifmap_vector_o = ifm_vector_i;
        end
        else if (load_second_i) begin
            for (pe_idx_r = 0; pe_idx_r < (COL_PE_NUM-1); pe_idx_r = pe_idx_r + 1) begin
                ifmap_vector_o[(pe_idx_r*DWIDTH) +: DWIDTH] = pe_buffer_r[pe_idx_r+1];
            end

            ifmap_vector_o[((COL_PE_NUM-1)*DWIDTH) +: DWIDTH] =
                ifm_vector_i[0 +: DWIDTH];
        end
        else if (shift_i) begin
            for (pe_idx_r = 0; pe_idx_r < (COL_PE_NUM-1); pe_idx_r = pe_idx_r + 1) begin
                ifmap_vector_o[(pe_idx_r*DWIDTH) +: DWIDTH] = pe_buffer_r[pe_idx_r+1];
            end

            ifmap_vector_o[((COL_PE_NUM-1)*DWIDTH) +: DWIDTH] = line_buffer_r[0];
        end
    end

    //-------------------------------------//
    //             Registers               //
    //-------------------------------------//
    always @(posedge CLK or negedge RST) begin
        if (!RST) begin
            for (pe_idx_r = 0; pe_idx_r < COL_PE_NUM; pe_idx_r = pe_idx_r + 1) begin
                pe_buffer_r[pe_idx_r] <= {DWIDTH{1'b0}};
            end

            for (line_idx_r = 0; line_idx_r < LINE_REG_NUM; line_idx_r = line_idx_r + 1) begin
                line_buffer_r[line_idx_r] <= {DWIDTH{1'b0}};
            end
        end
        else if (clear_i) begin
            for (pe_idx_r = 0; pe_idx_r < COL_PE_NUM; pe_idx_r = pe_idx_r + 1) begin
                pe_buffer_r[pe_idx_r] <= {DWIDTH{1'b0}};
            end

            for (line_idx_r = 0; line_idx_r < LINE_REG_NUM; line_idx_r = line_idx_r + 1) begin
                line_buffer_r[line_idx_r] <= {DWIDTH{1'b0}};
            end
        end
        else if (load_first_i) begin
            for (pe_idx_r = 0; pe_idx_r < COL_PE_NUM; pe_idx_r = pe_idx_r + 1) begin
                pe_buffer_r[pe_idx_r] <= ifm_vector_i[(pe_idx_r*DWIDTH) +: DWIDTH];
            end
        end
        else if (load_second_i) begin
            for (pe_idx_r = 0; pe_idx_r < (COL_PE_NUM-1); pe_idx_r = pe_idx_r + 1) begin
                pe_buffer_r[pe_idx_r] <= pe_buffer_r[pe_idx_r+1];
            end

            pe_buffer_r[COL_PE_NUM-1] <= ifm_vector_i[0 +: DWIDTH];

            for (line_idx_r = 0; line_idx_r < LINE_REG_NUM; line_idx_r = line_idx_r + 1) begin
                line_buffer_r[line_idx_r] <=
                    ifm_vector_i[((line_idx_r+1)*DWIDTH) +: DWIDTH];
            end
        end
        else if (shift_i) begin
            for (pe_idx_r = 0; pe_idx_r < (COL_PE_NUM-1); pe_idx_r = pe_idx_r + 1) begin
                pe_buffer_r[pe_idx_r] <= pe_buffer_r[pe_idx_r+1];
            end

            pe_buffer_r[COL_PE_NUM-1] <= line_buffer_r[0];

            for (line_idx_r = 0; line_idx_r < (LINE_REG_NUM-1); line_idx_r = line_idx_r + 1) begin
                line_buffer_r[line_idx_r] <= line_buffer_r[line_idx_r+1];
            end

            line_buffer_r[LINE_REG_NUM-1] <= {DWIDTH{1'b0}};
        end
    end

endmodule

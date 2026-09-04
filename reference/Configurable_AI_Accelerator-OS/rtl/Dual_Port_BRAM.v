`timescale 1 ns / 1 ps

// =============================================================================
// Dual-port-like memory wrapper for FPGA and ASIC flows.
//
// USE_ASIC_SRAM = 0:
//   Inferred synchronous RAM for RTL simulation and FPGA synthesis.
//   Both external ports share CLK and are implemented in one clocked process
//   to avoid multiple-driver errors in Synopsys Design Compiler.
//   If both ports write the same address in one cycle, port B has priority.
//
// USE_ASIC_SRAM = 1:
//   The two external ports are time-shared onto OpenRAM 1RW hard macros.
//   Port B has priority whenever port_b_en_i is asserted.
//
//   This arbitration is valid for the current accelerator schedule:
//     - Port A is used by the host during initialization/readback.
//     - Port B is used by the controller during accelerator execution.
//     - The two clients must not require simultaneous accesses.
//
// Supported native OpenRAM configurations:
//   AWIDTH=10, DWIDTH=16 : SRAM_16x1024_1rw
//   AWIDTH=11, DWIDTH=16 : SRAM_16x2048_1rw
//   AWIDTH=12, DWIDTH=16 : SRAM_16x4096_1rw
//   AWIDTH= 8, DWIDTH=16 : SRAM_16x256_1rw
//   AWIDTH= 8, DWIDTH=64 : 2 x SRAM_32x256_1rw
// =============================================================================
module Dual_Port_BRAM #(
    parameter AWIDTH        = 10,
    parameter DWIDTH        = 32,
    parameter USE_ASIC_SRAM = 0
)(
    input  wire                 CLK,

    //================================//
    //             Port A             //
    //================================//
    input  wire                 port_a_en_i,
    input  wire                 port_a_we_i,
    input  wire [AWIDTH-1:0]    port_a_addr_i,
    input  wire [DWIDTH-1:0]    port_a_data_i,
    output wire [DWIDTH-1:0]    port_a_data_o,

    //================================//
    //             Port B             //
    //================================//
    input  wire                 port_b_en_i,
    input  wire                 port_b_we_i,
    input  wire [AWIDTH-1:0]    port_b_addr_i,
    input  wire [DWIDTH-1:0]    port_b_data_i,
    output wire [DWIDTH-1:0]    port_b_data_o
);

    generate
        // =====================================================================
        // RTL / FPGA inferred-memory implementation
        // =====================================================================
        if (USE_ASIC_SRAM == 0) begin : gen_rtl_memory
            (* ram_style = "block" *)
            reg [DWIDTH-1:0] mem_r [0:(1 << AWIDTH)-1];

            reg [DWIDTH-1:0] port_a_data_r;
            reg [DWIDTH-1:0] port_b_data_r;

            // Synchronous read, read-first behavior.
            // A single process avoids multiple drivers in DC/Presto.
            always @(posedge CLK) begin
                if (port_a_en_i) begin
                    port_a_data_r <= mem_r[port_a_addr_i];
                end

                if (port_b_en_i) begin
                    port_b_data_r <= mem_r[port_b_addr_i];
                end

                if (port_a_en_i && port_a_we_i) begin
                    mem_r[port_a_addr_i] <= port_a_data_i;
                end

                // This later nonblocking assignment gives Port B priority if
                // both ports write the same address in the same cycle.
                if (port_b_en_i && port_b_we_i) begin
                    mem_r[port_b_addr_i] <= port_b_data_i;
                end
            end

            assign port_a_data_o = port_a_data_r;
            assign port_b_data_o = port_b_data_r;
        end

        // =====================================================================
        // ASIC OpenRAM hard-macro implementation
        // =====================================================================
        else begin : gen_asic_memory
            wire                 use_port_b_w;
            wire                 macro_en_w;
            wire                 macro_we_w;
            wire [AWIDTH-1:0]    macro_addr_w;
            wire [DWIDTH-1:0]    macro_data_i_w;
            wire [DWIDTH-1:0]    macro_data_o_w;

            // Port B has priority whenever it is enabled.
            assign use_port_b_w  = port_b_en_i;
            assign macro_en_w    = port_a_en_i | port_b_en_i;
            assign macro_we_w    = use_port_b_w ? port_b_we_i   : port_a_we_i;
            assign macro_addr_w  = use_port_b_w ? port_b_addr_i : port_a_addr_i;
            assign macro_data_i_w = use_port_b_w ? port_b_data_i : port_a_data_i;

            // The physical SRAM is 1RW, therefore both external read outputs
            // observe the same selected macro output. The surrounding design
            // must use only the output belonging to the active requester.
            assign port_a_data_o = macro_data_o_w;
            assign port_b_data_o = macro_data_o_w;

            // -----------------------------------------------------------------
            // Feature-map bank: 16-bit x 1024
            // -----------------------------------------------------------------
            if ((AWIDTH == 10) && (DWIDTH == 16)) begin : gen_sram_16x1024
                SRAM_16x1024_1rw u_sram (
                    .clk0  (CLK),
                    .csb0  (~macro_en_w),
                    .web0  (~macro_we_w),
                    .addr0 (macro_addr_w[9:0]),
                    .din0  (macro_data_i_w[15:0]),
                    .dout0 (macro_data_o_w[15:0])
                );
            end

            // -----------------------------------------------------------------
            // Optional 16-bit x 2048 configuration
            // -----------------------------------------------------------------
            else if ((AWIDTH == 11) && (DWIDTH == 16)) begin : gen_sram_16x2048
                SRAM_16x2048_1rw u_sram (
                    .clk0  (CLK),
                    .csb0  (~macro_en_w),
                    .web0  (~macro_we_w),
                    .addr0 (macro_addr_w[10:0]),
                    .din0  (macro_data_i_w[15:0]),
                    .dout0 (macro_data_o_w[15:0])
                );
            end

            // -----------------------------------------------------------------
            // Weight bank: 16-bit x 4096
            // -----------------------------------------------------------------
            else if ((AWIDTH == 12) && (DWIDTH == 16)) begin : gen_sram_16x4096
                SRAM_16x4096_1rw u_sram (
                    .clk0  (CLK),
                    .csb0  (~macro_en_w),
                    .web0  (~macro_we_w),
                    .addr0 (macro_addr_w[11:0]),
                    .din0  (macro_data_i_w[15:0]),
                    .dout0 (macro_data_o_w[15:0])
                );
            end

            // -----------------------------------------------------------------
            // Bias bank: 16-bit x 256
            // -----------------------------------------------------------------
            else if ((AWIDTH == 8) && (DWIDTH == 16)) begin : gen_sram_16x256
                SRAM_16x256_1rw u_sram (
                    .clk0  (CLK),
                    .csb0  (~macro_en_w),
                    .web0  (~macro_we_w),
                    .addr0 (macro_addr_w[7:0]),
                    .din0  (macro_data_i_w[15:0]),
                    .dout0 (macro_data_o_w[15:0])
                );
            end

            // -----------------------------------------------------------------
            // Instruction memory: 64-bit x 256
            // Implemented by two native 32-bit x 256 macros in parallel.
            // -----------------------------------------------------------------
            else if ((AWIDTH == 8) && (DWIDTH == 64)) begin : gen_sram_64x256
                wire [31:0] instruction_low_w;
                wire [31:0] instruction_high_w;

                SRAM_32x256_1rw u_sram_low (
                    .clk0  (CLK),
                    .csb0  (~macro_en_w),
                    .web0  (~macro_we_w),
                    .addr0 (macro_addr_w[7:0]),
                    .din0  (macro_data_i_w[31:0]),
                    .dout0 (instruction_low_w)
                );

                SRAM_32x256_1rw u_sram_high (
                    .clk0  (CLK),
                    .csb0  (~macro_en_w),
                    .web0  (~macro_we_w),
                    .addr0 (macro_addr_w[7:0]),
                    .din0  (macro_data_i_w[63:32]),
                    .dout0 (instruction_high_w)
                );

                assign macro_data_o_w = {
                    instruction_high_w,
                    instruction_low_w
                };
            end

            // -----------------------------------------------------------------
            // Unsupported ASIC shape
            // -----------------------------------------------------------------
            else begin : gen_unsupported_sram_shape
                // Keep an unsupported shape visible in simulation/elaboration
                // instead of silently inferring a large standard-cell memory.
                assign macro_data_o_w = {DWIDTH{1'b0}};
            end
        end
    endgenerate

endmodule

`timescale 1ns / 1ps

module tb_smoke;

    reg  [15:0] a_r;
    reg  [15:0] b_r;
    wire [15:0] sum_w;

    // Instantiate simple adder from rtl/
    smoke_adder u_adder (
        .a_i   (a_r),
        .b_i   (b_r),
        .sum_o (sum_w)
    );

    initial begin
        // Dump waveform for GTKWave
        $dumpfile("build/tb_smoke.vcd");
        $dumpvars(0, tb_smoke);

        $display("===================================================");
        $display("   [SMOKE TEST] Pure Verilog Environment Test     ");
        $display("===================================================");

        // Test 1: 10 + 20 = 30
        a_r = 16'd10;
        b_r = 16'd20;
        #10;
        $display("Test 1: a_i = %0d, b_i = %0d -> sum_o = %0d (Expected: 30)", a_r, b_r, sum_w);
        if (sum_w !== 16'd30) begin
            $display("[FAIL] Calculation mismatch!");
            $fatal(1);
        end

        // Test 2: 1250 + 3750 = 5000
        a_r = 16'd1250;
        b_r = 16'd3750;
        #10;
        $display("Test 2: a_i = %0d, b_i = %0d -> sum_o = %0d (Expected: 5000)", a_r, b_r, sum_w);
        if (sum_w !== 16'd5000) begin
            $display("[FAIL] Calculation mismatch!");
            $fatal(1);
        end

        #10;
        $display("---------------------------------------------------");
        $display("[SUCCESS] All Verilog smoke tests passed!");
        $display("Waveform saved to: build/tb_smoke.vcd");
        $display("===================================================");
        $finish;
    end

endmodule

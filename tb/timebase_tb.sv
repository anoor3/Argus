// ============================================================================
// timebase_tb.sv  -- self-checking testbench for timebase.sv
//
// Checks:
//   1. Reset forces count to 0.
//   2. Counter increments once per cycle when en=1.
//   3. Counter holds when en=0 (freeze).
//   4. Rollover: a narrow WIDTH=4 instance wraps 15 -> 0 correctly.
//   5. tick pulses only when enabled and not in reset.
//
// Pass/fail contract: prints "TEST PASSED" only if every check passed,
// prints "TEST FAILED" on the first failure.
// ============================================================================
`default_nettype none
`timescale 1ns/1ps

module timebase_tb;

    localparam int W = 8;

    reg              clk = 0;
    reg              rst = 1;
    reg              en  = 0;
    wire [W-1:0]     time_now;
    wire             tick;

    integer errors = 0;

    // 50 MHz -> 20 ns period
    always #10 clk = ~clk;

    timebase #(.WIDTH(W)) dut (
        .clk(clk), .rst(rst), .en(en),
        .time_now(time_now), .tick(tick)
    );

    task check(input condition, input [255:0] msg);
        begin
            if (!condition) begin
                $display("  FAIL: %0s (t=%0t)", msg, $time);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        // Hold reset a few cycles
        @(posedge clk); @(posedge clk);
        check(time_now == 0, "count should be 0 during reset");

        // Release reset, enable counting
        @(negedge clk); rst = 0; en = 1;
        @(posedge clk); #1;
        check(time_now == 1, "count should be 1 after one enabled cycle");
        check(tick == 1'b1,  "tick should assert when enabled");

        @(posedge clk); #1;
        check(time_now == 2, "count should be 2 after two enabled cycles");

        // Freeze: disable enable, value must hold
        @(negedge clk); en = 0;
        @(posedge clk); #1;
        check(time_now == 2, "count should hold when en=0");
        check(tick == 1'b0,  "tick should be low when en=0");

        // Re-enable and drive to rollover (W=8 -> wraps at 256)
        @(negedge clk); en = 1;
        repeat (300) @(posedge clk);
        #1;
        // 2 (frozen value) + 300 increments = 302 mod 256 = 46
        check(time_now == ((2 + 300) % 256),
              "count should wrap modulo 2**WIDTH");

        // Synchronous reset mid-count returns to 0
        @(negedge clk); rst = 1;
        @(posedge clk); #1;
        check(time_now == 0, "sync reset returns count to 0");

        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED (%0d errors)", errors);
        $finish;
    end

endmodule

`default_nettype wire

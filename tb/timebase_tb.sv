// ============================================================================
// timebase_tb.sv  -- self-checking testbench for timebase.sv
//
// Checks:
//   1. Reset forces count to 0.
//   2. Counter increments once per cycle when en=1.
//   3. Counter holds when en=0 (freeze).
//   4. Rollover: a narrow WIDTH=8 instance wraps at 256 correctly.
//   5. tick pulses only when enabled and not in reset.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module timebase_tb;

    localparam int W = 8;

    reg              clk = 0;
    reg              rst = 1;
    reg              en  = 0;
    wire [W-1:0]     time_now;
    wire             tick;

    integer errors = 0;

    always #10 clk = ~clk;  // 50 MHz

    timebase #(.WIDTH(W)) dut (
        .clk(clk), .rst(rst), .en(en),
        .time_now(time_now), .tick(tick)
    );

    initial begin
        @(posedge clk); @(posedge clk);
        `CHECK(time_now == 0, "count should be 0 during reset")

        @(negedge clk); rst = 0; en = 1;
        @(posedge clk); #1;
        `CHECK_EQ(time_now, 8'd1, "count after one enabled cycle")
        `CHECK(tick == 1'b1, "tick should assert when enabled")

        @(posedge clk); #1;
        `CHECK_EQ(time_now, 8'd2, "count after two enabled cycles")

        // Freeze
        @(negedge clk); en = 0;
        @(posedge clk); #1;
        `CHECK_EQ(time_now, 8'd2, "count should hold when en=0")
        `CHECK(tick == 1'b0, "tick should be low when en=0")

        // Rollover: 2 + 300 = 302 mod 256 = 46
        @(negedge clk); en = 1;
        repeat (300) @(posedge clk);
        #1;
        `CHECK_EQ(time_now, ((2 + 300) % 256), "count should wrap mod 2**WIDTH")

        // Sync reset mid-count
        @(negedge clk); rst = 1;
        @(posedge clk); #1;
        `CHECK_EQ(time_now, 8'd0, "sync reset returns count to 0")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// trigger_engine_edge_tb.sv -- re-arm after freeze
//
// After a trigger freezes capture, a fresh `arm` must clear triggered and
// resume capture, and a subsequent match must trigger again. Proves the engine
// is reusable across multiple acquisitions.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module trigger_engine_edge_tb;

    reg        clk = 0, rst = 1, arm = 0;
    reg  [7:0] match_src = 8'h02, match_code = 8'h10;
    reg  [15:0] post_count = 16'd0;
    reg        ev_valid = 0;
    reg  [7:0] ev_src = 0, ev_code = 0;
    wire       capture_en, triggered, trig_pulse;

    integer errors = 0;
    integer pulses = 0;

    always #10 clk = ~clk;
    `WATCHDOG(400000)

    trigger_engine dut (
        .clk(clk), .rst(rst), .arm(arm),
        .match_src(match_src), .match_code(match_code), .post_count(post_count),
        .ev_valid(ev_valid), .ev_src(ev_src), .ev_code(ev_code),
        .capture_en(capture_en), .triggered(triggered), .trig_pulse(trig_pulse)
    );

    always @(posedge clk) if (!rst && trig_pulse) pulses = pulses + 1;

    task ev(input [7:0] s, input [7:0] c);
        begin @(negedge clk); ev_valid=1; ev_src=s; ev_code=c; @(negedge clk); ev_valid=0; end
    endtask
    task do_arm; begin @(negedge clk); arm=1; @(negedge clk); arm=0; end endtask

    initial begin
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;

        // First acquisition: arm, match, freeze
        do_arm; ev(8'h02, 8'h10);
        repeat (2) @(posedge clk);
        `CHECK(triggered == 1'b1, "first trigger fires")
        `CHECK(capture_en == 1'b0, "frozen after first trigger")

        // Re-arm: triggered clears, capture resumes
        do_arm;
        `CHECK(triggered == 1'b0, "re-arm clears triggered")
        `CHECK(capture_en == 1'b1, "re-arm resumes capture")

        // Second match triggers again
        ev(8'h02, 8'h10);
        repeat (2) @(posedge clk);
        `CHECK(triggered == 1'b1, "second trigger fires after re-arm")
        `CHECK_EQ(pulses, 2, "exactly two trigger pulses across two acquisitions")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

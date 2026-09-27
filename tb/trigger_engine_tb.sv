// ============================================================================
// trigger_engine_tb.sv -- self-checking testbench for trigger_engine.sv
//
// Checks:
//   1. After arm, a non-matching event does not trigger.
//   2. A matching event sets triggered and pulses trig_pulse.
//   3. With post_count=0, capture_en drops immediately (freeze on match).
//   4. With post_count=2, capture stays on for exactly 2 more events, then
//      freezes.
//   5. Wildcard match (0xFF) triggers on any event.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module trigger_engine_tb;

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

        // --- Case A: freeze-on-match (post_count=0) ---
        post_count = 16'd0; match_src=8'h02; match_code=8'h10;
        do_arm;
        ev(8'h01, 8'h01);            // non-matching
        `CHECK(triggered == 1'b0, "no trigger on non-matching event")
        `CHECK(capture_en == 1'b1, "capture stays on before match")
        ev(8'h02, 8'h10);            // matching
        repeat (2) @(posedge clk);
        `CHECK(triggered == 1'b1, "triggered on matching event")
        `CHECK(capture_en == 1'b0, "capture freezes immediately (post=0)")
        `CHECK_EQ(pulses, 1, "exactly one trig_pulse")

        // --- Case B: post_count=2 keeps capturing 2 more events ---
        pulses = 0;
        post_count = 16'd2; match_src=8'h03; match_code=8'h20;
        do_arm;
        ev(8'h03, 8'h20);            // match -> enter POST(2)
        `CHECK(capture_en == 1'b1, "still capturing during post window")
        ev(8'h01, 8'h01);            // post event 1
        `CHECK(capture_en == 1'b1, "capturing after 1 post event")
        ev(8'h01, 8'h02);            // post event 2 -> freeze
        repeat (2) @(posedge clk);
        `CHECK(capture_en == 1'b0, "freeze after post_count events")

        // --- Case C: wildcard match ---
        match_src = 8'hFF; match_code = 8'hFF; post_count = 16'd0;
        do_arm;
        ev(8'h07, 8'h07);            // any event should match
        repeat (2) @(posedge clk);
        `CHECK(triggered == 1'b1, "wildcard matches any event")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

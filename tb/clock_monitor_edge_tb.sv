// ============================================================================
// clock_monitor_edge_tb.sv -- clock recovery (lost -> ok) sequence
//
// clock_monitor_tb covers alive then lost. This covers the return path:
// a clock that stops (CLK_LOST) and then restarts must emit CLK_OK again,
// proving the state transition is edge-triggered both ways.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_check.svh"

module clock_monitor_edge_tb;

    reg        clk = 0, rst = 1;
    reg        dut_clk = 0;
    reg  [15:0] window_cyc = 16'd40, min_edges = 16'd3;
    wire       ev_valid;
    wire [7:0] ev_code;
    wire [15:0] ev_value;

    integer errors = 0;
    integer ok_seen = 0, lost_seen = 0;

    always #10 clk = ~clk;
    `WATCHDOG(2000000)

    reg run_clk = 0;
    always #35 if (run_clk) dut_clk = ~dut_clk;

    clock_monitor dut (
        .clk(clk), .rst(rst), .dut_clk_in(dut_clk),
        .window_cyc(window_cyc), .min_edges(min_edges),
        .ev_valid(ev_valid), .ev_code(ev_code), .ev_value(ev_value)
    );

    always @(posedge clk) if (!rst && ev_valid) begin
        if (ev_code == `EVC_CLK_OK)   ok_seen   = ok_seen + 1;
        if (ev_code == `EVC_CLK_LOST) lost_seen = lost_seen + 1;
    end

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;

        // running -> CLK_OK
        run_clk = 1; repeat (150) @(posedge clk);
        `CHECK(ok_seen >= 1, "CLK_OK while running")

        // stop -> CLK_LOST
        run_clk = 0; dut_clk = 0; repeat (150) @(posedge clk);
        `CHECK(lost_seen >= 1, "CLK_LOST after stop")

        // restart -> CLK_OK again (recovery)
        ok_seen = 0;
        run_clk = 1; repeat (200) @(posedge clk);
        `CHECK(ok_seen >= 1, "CLK_OK again after clock recovers")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

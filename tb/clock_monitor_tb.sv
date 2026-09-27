// ============================================================================
// clock_monitor_tb.sv -- self-checking testbench for clock_monitor.sv
//
// Checks:
//   1. A running DUT clock produces an EVC_CLK_OK event.
//   2. Stopping the DUT clock produces an EVC_CLK_LOST event.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_check.svh"

module clock_monitor_tb;

    reg        clk = 0, rst = 1;
    reg        dut_clk = 0;
    reg  [15:0] window_cyc = 16'd40;
    reg  [15:0] min_edges  = 16'd3;
    wire       ev_valid;
    wire [7:0] ev_code;
    wire [15:0] ev_value;

    integer errors = 0;
    integer ok_seen = 0, lost_seen = 0;

    always #10 clk = ~clk;      // ARGUS 50 MHz
    `WATCHDOG(1000000)

    // DUT clock generator, gated by run_clk
    reg run_clk = 0;
    always #35 if (run_clk) dut_clk = ~dut_clk;  // ~14 MHz when running

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

        // Run the DUT clock for several windows
        run_clk = 1;
        repeat (200) @(posedge clk);
        `CHECK(ok_seen >= 1, "clock alive produces CLK_OK")

        // Stop the DUT clock; hold it static for several windows
        run_clk = 0; dut_clk = 0;
        repeat (200) @(posedge clk);
        `CHECK(lost_seen >= 1, "clock stopped produces CLK_LOST")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

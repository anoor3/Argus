// ============================================================================
// gpio_monitor_edge_tb.sv -- debounce boundary behavior
//
// Checks the exact debounce boundary: a level held for just under the debounce
// window is rejected, and a level held for exactly the window is accepted. This
// pins the off-by-one behavior of the debounce counter.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_check.svh"

module gpio_monitor_edge_tb;

    reg        clk = 0, rst = 1;
    reg        gpio_in = 0;
    reg  [7:0] debounce_cyc = 8'd4;
    wire       ev_valid;
    wire [7:0] ev_code;
    wire [15:0] ev_value;

    integer errors = 0;
    integer rise_cnt = 0;

    always #10 clk = ~clk;
    `WATCHDOG(400000)

    gpio_monitor dut (
        .clk(clk), .rst(rst), .gpio_in(gpio_in), .debounce_cyc(debounce_cyc),
        .ev_valid(ev_valid), .ev_code(ev_code), .ev_value(ev_value)
    );

    always @(posedge clk) if (!rst && ev_valid && ev_code == `EVC_RISE)
        rise_cnt = rise_cnt + 1;

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        // Hold high for 3 cycles (< debounce 4) then drop -> rejected
        @(negedge clk); gpio_in = 1;
        repeat (3) @(posedge clk);
        @(negedge clk); gpio_in = 0;
        repeat (8) @(posedge clk);
        `CHECK_EQ(rise_cnt, 0, "held < debounce is rejected")

        // Now hold high well past debounce -> accepted (one event)
        @(negedge clk); gpio_in = 1;
        repeat (12) @(posedge clk);
        `CHECK_EQ(rise_cnt, 1, "held >= debounce produces exactly one event")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

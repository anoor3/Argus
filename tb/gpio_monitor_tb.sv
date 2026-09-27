// ============================================================================
// gpio_monitor_tb.sv -- self-checking testbench for gpio_monitor.sv
//
// Checks:
//   1. A clean rising edge (held) produces one EVC_RISE event.
//   2. A clean falling edge produces one EVC_FALL event.
//   3. A glitch shorter than the debounce window produces NO event.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_check.svh"

module gpio_monitor_tb;

    reg        clk = 0, rst = 1;
    reg        gpio_in = 0;
    reg  [7:0] debounce_cyc = 8'd3;
    wire       ev_valid;
    wire [7:0] ev_code;
    wire [15:0] ev_value;

    integer errors = 0;
    integer rise_cnt = 0, fall_cnt = 0;

    always #10 clk = ~clk;
    `WATCHDOG(400000)

    gpio_monitor dut (
        .clk(clk), .rst(rst), .gpio_in(gpio_in),
        .debounce_cyc(debounce_cyc),
        .ev_valid(ev_valid), .ev_code(ev_code), .ev_value(ev_value)
    );

    always @(posedge clk) if (!rst && ev_valid) begin
        if (ev_code == `EVC_RISE) rise_cnt = rise_cnt + 1;
        if (ev_code == `EVC_FALL) fall_cnt = fall_cnt + 1;
    end

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        // Clean rising edge, hold well past debounce
        @(negedge clk); gpio_in = 1;
        repeat (12) @(posedge clk);
        `CHECK_EQ(rise_cnt, 1, "one rising event on clean edge")

        // Clean falling edge
        @(negedge clk); gpio_in = 0;
        repeat (12) @(posedge clk);
        `CHECK_EQ(fall_cnt, 1, "one falling event on clean edge")

        // Glitch: go high for only 1 cycle (< debounce=3), then back low
        @(negedge clk); gpio_in = 1;
        @(posedge clk);
        @(negedge clk); gpio_in = 0;
        repeat (12) @(posedge clk);
        `CHECK_EQ(rise_cnt, 1, "glitch shorter than debounce produces no event")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

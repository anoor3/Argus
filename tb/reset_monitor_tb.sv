// ============================================================================
// reset_monitor_tb.sv -- self-checking testbench for reset_monitor.sv
//
// Checks:
//   1. Reset assertion emits EVC_RST_ASSERT.
//   2. Reset deassertion emits EVC_RST_DEASSRT.
//   3. The reported width on deassert is nonzero and roughly matches the hold.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_check.svh"

module reset_monitor_tb;

    reg        clk = 0, rst = 1;
    reg        dut_rst_in = 0;
    wire       ev_valid;
    wire [7:0] ev_code;
    wire [15:0] ev_value;

    integer errors = 0;
    integer assert_seen = 0, deassert_seen = 0;
    reg [15:0] last_width = 0;

    always #10 clk = ~clk;
    `WATCHDOG(400000)

    reset_monitor dut (
        .clk(clk), .rst(rst), .dut_rst_in(dut_rst_in),
        .ev_valid(ev_valid), .ev_code(ev_code), .ev_value(ev_value)
    );

    always @(posedge clk) if (!rst && ev_valid) begin
        if (ev_code == `EVC_RST_ASSERT)  assert_seen  = assert_seen + 1;
        if (ev_code == `EVC_RST_DEASSRT) begin
            deassert_seen = deassert_seen + 1;
            last_width    = ev_value;
        end
    end

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        // Assert reset and hold ~10 cycles
        @(negedge clk); dut_rst_in = 1;
        repeat (10) @(posedge clk);
        @(negedge clk); dut_rst_in = 0;
        repeat (5) @(posedge clk);

        `CHECK_EQ(assert_seen, 1, "one assert event")
        `CHECK_EQ(deassert_seen, 1, "one deassert event")
        `CHECK(last_width >= 16'd8, "measured reset width is plausible (>=8)")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

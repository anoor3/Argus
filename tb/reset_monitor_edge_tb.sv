// ============================================================================
// reset_monitor_edge_tb.sv -- back-to-back reset pulses and width reset
//
// Verifies that a second, shorter reset pulse reports its own (shorter) width,
// i.e. the width counter is re-zeroed on each assertion rather than accumulated.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_check.svh"

module reset_monitor_edge_tb;

    reg        clk = 0, rst = 1;
    reg        dut_rst_in = 0;
    wire       ev_valid;
    wire [7:0] ev_code;
    wire [15:0] ev_value;

    integer errors = 0;
    reg [15:0] first_width = 0, second_width = 0;
    integer deassert_n = 0;

    always #10 clk = ~clk;
    `WATCHDOG(600000)

    reset_monitor dut (
        .clk(clk), .rst(rst), .dut_rst_in(dut_rst_in),
        .ev_valid(ev_valid), .ev_code(ev_code), .ev_value(ev_value)
    );

    always @(posedge clk) if (!rst && ev_valid && ev_code == `EVC_RST_DEASSRT) begin
        deassert_n = deassert_n + 1;
        if (deassert_n == 1) first_width  = ev_value;
        if (deassert_n == 2) second_width = ev_value;
    end

    task pulse_reset(input integer cycles);
        integer k;
        begin
            @(negedge clk); dut_rst_in = 1;
            for (k=0;k<cycles;k=k+1) @(posedge clk);
            @(negedge clk); dut_rst_in = 0;
            repeat (5) @(posedge clk);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        pulse_reset(12);   // long
        pulse_reset(4);    // short

        `CHECK_EQ(deassert_n, 2, "two deassert events")
        `CHECK(first_width  >= 16'd10, "first (long) width is large")
        `CHECK(second_width <  first_width, "second (short) width is smaller, not accumulated")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

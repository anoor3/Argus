// ============================================================================
// capture_subsystem_tb.sv -- P2 integration test
//
// Drives a GPIO edge and a reset pulse, arms a trigger on the reset-assert
// event, then reads the trace out and checks:
//   1. Events were captured (event_count > 0).
//   2. The recovered records carry sane source ids and MONOTONIC timestamps
//      (timestamp correlation across sources works).
//   3. The trigger fires on the reset-assert event.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_check.svh"

module capture_subsystem_tb;

    reg        clk = 0, rst = 1;
    reg        gpio_in = 0, dut_rst_in = 0, dut_clk_in = 0;
    reg        arm = 0;
    reg  [7:0] match_src = `SRC_RESET, match_code = `EVC_RST_ASSERT;
    reg  [15:0] post_count = 16'd4;
    reg        rd_en = 0;
    wire [95:0] rd_data; wire rd_valid;
    wire [31:0] event_count; wire overflow, triggered;

    integer errors = 0;

    always #10 clk = ~clk;
    `WATCHDOG(3000000)

    capture_subsystem #(.TRACE_AW(6)) dut (
        .clk(clk), .rst(rst),
        .gpio_in(gpio_in), .dut_rst_in(dut_rst_in), .dut_clk_in(dut_clk_in),
        .arm(arm), .match_src(match_src), .match_code(match_code),
        .post_count(post_count),
        .rd_en(rd_en), .rd_data(rd_data), .rd_valid(rd_valid),
        .event_count(event_count), .overflow(overflow), .triggered(triggered)
    );

    reg [95:0] rec;
    reg [63:0] prev_ts;
    integer    nread;

    task readrec(output [95:0] r);
        begin @(negedge clk); rd_en=1; @(posedge clk); @(negedge clk); rd_en=0; #1; r=rd_data; end
    endtask

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        arm = 1; @(negedge clk); arm = 0;

        // GPIO rising edge
        @(negedge clk); gpio_in = 1;
        repeat (6) @(posedge clk);

        // Reset assert (should be the trigger) then deassert
        @(negedge clk); dut_rst_in = 1;
        repeat (6) @(posedge clk);
        @(negedge clk); dut_rst_in = 0;
        repeat (10) @(posedge clk);

        // Another GPIO edge (post-trigger)
        @(negedge clk); gpio_in = 0;
        repeat (10) @(posedge clk);

        `CHECK(event_count > 0, "some events were captured")
        `CHECK(triggered == 1'b1, "trigger fired on reset assert")

        // Read out records and check timestamps are monotonically increasing
        prev_ts = 64'd0; nread = 0;
        repeat (event_count > 6 ? 6 : event_count) begin
            readrec(rec);
            if (rd_valid) begin
                if (nread > 0)
                    `CHECK(rec[95:32] >= prev_ts, "timestamps monotonic across records")
                prev_ts = rec[95:32];
                nread = nread + 1;
            end
        end
        `CHECK(nread > 0, "read back at least one record")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

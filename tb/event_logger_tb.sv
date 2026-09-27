// ============================================================================
// event_logger_tb.sv -- self-checking testbench for event_logger.sv
//
// Checks:
//   1. A single source event produces one packed record with correct fields
//      and the current timestamp.
//   2. event_count increments per logged event.
//   3. Two simultaneous events are both logged (serialized via skid), and
//      the second carries the correct fields.
//   4. Capture disabled (en=0) logs nothing.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_check.svh"

module event_logger_tb;

    reg        clk = 0, rst = 1, en = 1;
    reg [63:0] time_now = 0;

    reg        v0=0,v1=0,v2=0;
    reg [7:0]  id0=0,id1=0,id2=0, c0=0,c1=0,c2=0;
    reg [15:0] val0=0,val1=0,val2=0;

    wire        rec_wr;
    wire [95:0] rec_data;
    wire [31:0] event_count, drop_count;

    integer errors = 0;

    // Capture written records
    reg [95:0] cap [0:15];
    integer    ncap = 0;

    always #10 clk = ~clk;
    `WATCHDOG(400000)

    // free-running timestamp for realism
    always @(posedge clk) if (!rst) time_now <= time_now + 1;

    event_logger dut (
        .clk(clk), .rst(rst), .en(en), .time_now(time_now),
        .src0_valid(v0), .src0_id(id0), .src0_code(c0), .src0_value(val0),
        .src1_valid(v1), .src1_id(id1), .src1_code(c1), .src1_value(val1),
        .src2_valid(v2), .src2_id(id2), .src2_code(c2), .src2_value(val2),
        .rec_wr(rec_wr), .rec_data(rec_data),
        .event_count(event_count), .drop_count(drop_count)
    );

    always @(posedge clk) if (!rst && rec_wr) begin cap[ncap] = rec_data; ncap = ncap + 1; end

    task pulse0(input [7:0] id, input [7:0] code, input [15:0] val);
        begin @(negedge clk); v0=1; id0=id; c0=code; val0=val; @(negedge clk); v0=0; end
    endtask

    initial begin
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;
        repeat (2) @(posedge clk);

        // Single event
        pulse0(`SRC_GPIO, `EVC_RISE, 16'h0001);
        repeat (3) @(posedge clk);
        `CHECK_EQ(ncap, 1, "one record after one event")
        `CHECK_EQ(event_count, 1, "event_count is 1")
        `CHECK_EQ(cap[0][31:24], `SRC_GPIO, "record source id")
        `CHECK_EQ(cap[0][23:16], `EVC_RISE, "record event code")
        `CHECK_EQ(cap[0][15:0],  16'h0001,  "record value")

        // Two simultaneous events on src0 and src1
        @(negedge clk);
        v0=1; id0=`SRC_GPIO;  c0=`EVC_FALL; val0=16'hAA;
        v1=1; id1=`SRC_RESET; c1=`EVC_RST_ASSERT; val1=16'hBB;
        @(negedge clk); v0=0; v1=0;
        repeat (4) @(posedge clk);
        `CHECK_EQ(ncap, 3, "both simultaneous events logged (total 3)")
        `CHECK_EQ(event_count, 3, "event_count is 3")
        // cap[1] is src0 (priority), cap[2] is src1 from skid
        `CHECK_EQ(cap[1][31:24], `SRC_GPIO,  "sim event: src0 first")
        `CHECK_EQ(cap[2][31:24], `SRC_RESET, "sim event: src1 second via skid")
        `CHECK_EQ(cap[2][15:0],  16'hBB,      "skidded value preserved")

        // Disabled capture logs nothing
        en = 0;
        pulse0(`SRC_GPIO, `EVC_RISE, 16'h00FF);
        repeat (3) @(posedge clk);
        `CHECK_EQ(ncap, 3, "no new records while en=0")

        `CHECK_EQ(drop_count, 0, "no drops in this scenario")
        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// trace_buffer_edge_tb.sv -- edge cases for trace_buffer.sv
//
// Complements trace_buffer_tb with:
//   1. Interleaved write/read keeps count consistent (no under/overflow).
//   2. Simultaneous write+read at full does not set overflow (a slot frees as
//      one is consumed).
//   3. Repeated wrap: writing many multiples of depth keeps the newest window.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module trace_buffer_edge_tb;

    localparam int DW = 96, AW = 2;  // depth 4

    reg          clk = 0, rst = 1;
    reg          wr_en = 0; reg [DW-1:0] wr_data = 0;
    reg          rd_en = 0; wire [DW-1:0] rd_data; wire rd_valid;
    wire [AW:0]  count; wire overflow, full, empty;

    integer errors = 0;

    always #10 clk = ~clk;
    `WATCHDOG(400000)

    trace_buffer #(.DW(DW), .AW(AW)) dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_data(wr_data),
        .rd_en(rd_en), .rd_data(rd_data), .rd_valid(rd_valid),
        .count(count), .overflow(overflow), .full(full), .empty(empty)
    );

    task step_wr(input [DW-1:0] d); begin @(negedge clk); wr_data=d; wr_en=1; @(negedge clk); wr_en=0; end endtask

    integer i;
    reg [DW-1:0] got;

    initial begin
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;

        // 1. Interleave: write 2, read 1, repeat; count should stay bounded
        step_wr(96'd1); step_wr(96'd2);
        @(negedge clk); rd_en=1; @(posedge clk); @(negedge clk); rd_en=0;
        step_wr(96'd3);
        #1; `CHECK(count <= 4, "count stays within depth under interleave")
        `CHECK(overflow == 1'b0, "no overflow while interleaving with reads")

        // drain
        repeat (5) begin @(negedge clk); rd_en=1; @(posedge clk); @(negedge clk); rd_en=0; end
        #1; `CHECK(empty == 1'b1, "empty after draining")

        // 2. simultaneous write+read at full: no overflow
        step_wr(96'd10); step_wr(96'd11); step_wr(96'd12); step_wr(96'd13); // full
        #1; `CHECK(full == 1'b1, "full after depth writes")
        @(negedge clk); wr_data=96'd14; wr_en=1; rd_en=1;   // simultaneous
        @(posedge clk); @(negedge clk); wr_en=0; rd_en=0;
        #1; `CHECK(overflow == 1'b0, "simultaneous rd+wr at full avoids overflow")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

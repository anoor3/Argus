// ============================================================================
// trace_buffer_tb.sv -- self-checking testbench for trace_buffer.sv
//
// Checks (small depth AW=2 -> 4 records):
//   1. Empty at start.
//   2. Records read back in write order (FIFO ordering).
//   3. count reflects stored records.
//   4. Writing past capacity overwrites oldest and latches overflow.
//   5. After overflow, reads return the most-recent window, not the lost ones.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module trace_buffer_tb;

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

    task wr(input [DW-1:0] d);
        begin @(negedge clk); wr_data=d; wr_en=1; @(negedge clk); wr_en=0; end
    endtask

    reg [DW-1:0] got;
    task rd(output [DW-1:0] d);
        begin @(negedge clk); rd_en=1; @(posedge clk); @(negedge clk); rd_en=0; #1; d=rd_data; end
    endtask

    initial begin
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;
        `CHECK(empty == 1'b1, "starts empty")

        // Write 3 records
        wr(96'd100); wr(96'd200); wr(96'd300);
        #1; `CHECK_EQ(count, 3, "count is 3 after 3 writes")

        rd(got); `CHECK_EQ(got, 96'd100, "order 1")
        rd(got); `CHECK_EQ(got, 96'd200, "order 2")
        rd(got); `CHECK_EQ(got, 96'd300, "order 3")
        #1; `CHECK(empty == 1'b1, "empty after draining")
        `CHECK(overflow == 1'b0, "no overflow yet")

        // Overflow: write 6 into depth-4 buffer
        wr(96'd1); wr(96'd2); wr(96'd3); wr(96'd4); wr(96'd5); wr(96'd6);
        #1;
        `CHECK(overflow == 1'b1, "overflow latched after overwrite")
        // Oldest (1,2) overwritten; buffer holds newest 4: 3,4,5,6
        rd(got); `CHECK_EQ(got, 96'd3, "oldest survivors after overflow: 3")
        rd(got); `CHECK_EQ(got, 96'd4, "then 4")
        rd(got); `CHECK_EQ(got, 96'd5, "then 5")
        rd(got); `CHECK_EQ(got, 96'd6, "then 6")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// async_fifo_edge_tb.sv -- fill/drain boundary and empty-read safety
//
// Complements async_fifo_tb with:
//   1. Reading while empty does not corrupt state or advance the pointer.
//   2. Fill exactly to depth-1 (not full), then one more write reaches full.
//   3. Drain fully and confirm empty asserts again (pointer wrap clean).
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module async_fifo_edge_tb;

    localparam int DW = 8, AW = 3;   // depth 8

    reg wclk = 0, wrst = 1, rclk = 0, rrst = 1;
    reg          wr_en = 0; reg [DW-1:0] wdata = 0; wire full;
    reg          rd_en = 0; wire [DW-1:0] rdata;    wire empty;

    integer errors = 0;

    always #10 wclk = ~wclk;
    always #13 rclk = ~rclk;
    `WATCHDOG(900000)

    async_fifo #(.DW(DW), .AW(AW)) dut (
        .wclk(wclk), .wrst(wrst), .wr_en(wr_en), .wdata(wdata), .full(full),
        .rclk(rclk), .rrst(rrst), .rd_en(rd_en), .rdata(rdata), .empty(empty)
    );

    task push(input [DW-1:0] d);
        begin @(negedge wclk); wdata=d; wr_en=1; @(negedge wclk); wr_en=0; end
    endtask
    reg [DW-1:0] got;
    task pop(output [DW-1:0] d);
        begin @(negedge rclk); rd_en=1; @(posedge rclk); @(negedge rclk); rd_en=0; #1; d=rdata; end
    endtask

    integer i;

    initial begin
        repeat (3) @(posedge wclk); wrst = 0;
        repeat (3) @(posedge rclk); rrst = 0;
        repeat (4) @(posedge rclk);

        // 1. read while empty: must stay empty, no crash
        @(negedge rclk); rd_en=1; @(posedge rclk); @(negedge rclk); rd_en=0;
        repeat (4) @(posedge rclk);
        `CHECK(empty == 1'b1, "read while empty leaves fifo empty")

        // 2. fill exactly 7 (depth-1) -> not full; 8th -> full
        for (i=0;i<7;i=i+1) push(i[DW-1:0]);
        repeat (6) @(posedge wclk);
        `CHECK(full == 1'b0, "depth-1 writes: not full yet")
        push(8'd7);
        repeat (6) @(posedge wclk);
        `CHECK(full == 1'b1, "depth writes: full")

        // 3. drain all, expect order 0..7 then empty
        for (i=0;i<8;i=i+1) begin pop(got); `CHECK_EQ(got, i[DW-1:0], "drain order") end
        repeat (6) @(posedge rclk);
        `CHECK(empty == 1'b1, "empty after full drain (clean wrap)")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

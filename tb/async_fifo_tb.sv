// ============================================================================
// async_fifo_tb.sv -- self-checking testbench for async_fifo.sv
//
// Checks (write and read on different clocks):
//   1. FIFO starts empty.
//   2. Words written are read back in order (FIFO ordering preserved).
//   3. full asserts when depth words are queued; writes while full are dropped.
//   4. empty asserts again after draining.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module async_fifo_tb;

    localparam int DW = 8, AW = 3;  // depth 8

    reg wclk = 0, wrst = 1, rclk = 0, rrst = 1;
    reg          wr_en = 0; reg [DW-1:0] wdata = 0; wire full;
    reg          rd_en = 0; wire [DW-1:0] rdata;    wire empty;

    integer errors = 0;

    always #10 wclk = ~wclk;   // 50 MHz write
    always #13 rclk = ~rclk;   // ~38 MHz read

    `WATCHDOG(800000)

    async_fifo #(.DW(DW), .AW(AW)) dut (
        .wclk(wclk), .wrst(wrst), .wr_en(wr_en), .wdata(wdata), .full(full),
        .rclk(rclk), .rrst(rrst), .rd_en(rd_en), .rdata(rdata), .empty(empty)
    );

    task push(input [DW-1:0] d);
        begin @(negedge wclk); wdata = d; wr_en = 1; @(negedge wclk); wr_en = 0; end
    endtask

    reg [DW-1:0] got;
    task pop(output [DW-1:0] d);
        begin
            @(negedge rclk); rd_en = 1;
            @(posedge rclk); @(negedge rclk); rd_en = 0; #1; d = rdata;
        end
    endtask

    integer i;

    initial begin
        repeat (3) @(posedge wclk); wrst = 0;
        repeat (3) @(posedge rclk); rrst = 0;
        repeat (4) @(posedge rclk);

        `CHECK(empty == 1'b1, "fifo starts empty")

        // Push 4 values, let pointers sync, pop and check order
        push(8'h10); push(8'h20); push(8'h30); push(8'h40);
        repeat (6) @(posedge rclk);
        `CHECK(empty == 1'b0, "not empty after writes")

        pop(got); `CHECK_EQ(got, 8'h10, "read order 1");
        pop(got); `CHECK_EQ(got, 8'h20, "read order 2");
        pop(got); `CHECK_EQ(got, 8'h30, "read order 3");
        pop(got); `CHECK_EQ(got, 8'h40, "read order 4");
        repeat (6) @(posedge rclk);
        `CHECK(empty == 1'b1, "empty after draining all")

        // Fill to full (depth 8), then attempt an extra write which must drop
        for (i = 0; i < 8; i = i + 1) push(i[DW-1:0]);
        repeat (6) @(posedge wclk);
        `CHECK(full == 1'b1, "full after depth writes")
        push(8'hEE); // should be ignored
        repeat (6) @(posedge rclk);

        // First popped value must be 0 (the extra 0xEE was dropped, not queued)
        pop(got); `CHECK_EQ(got, 8'h00, "overflow write was dropped");

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

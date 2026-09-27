// ============================================================================
// csr_bank_edge_tb.sv -- read-before-write and back-to-back access edges
//
// Complements csr_bank_tb by pinning down the defined behavior when a read and
// a write hit the same RW register on the same cycle: the stored value updates
// (write wins) while the concurrent read returns the OLD value (read-before-
// write). Also checks back-to-back writes take effect in order.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module csr_bank_edge_tb;

    localparam int ADDRW = 8, DW = 32;

    reg              clk = 0, rst = 1;
    reg              wr_en = 0, rd_en = 0;
    reg  [ADDRW-1:0] addr = 0;
    reg  [DW-1:0]    wr_data = 0;
    wire [DW-1:0]    rd_data;
    wire             rd_valid;
    reg  [63:0]      time_now = 0;
    reg  [DW-1:0]    event_count = 0, status_in = 0;
    wire [DW-1:0]    ctrl_out, scratch_out;

    integer errors = 0;

    always #10 clk = ~clk;
    `WATCHDOG(300000)

    csr_bank #(.ADDRW(ADDRW), .DW(DW)) dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .rd_en(rd_en), .addr(addr),
        .wr_data(wr_data), .rd_data(rd_data), .rd_valid(rd_valid),
        .time_now(time_now), .event_count(event_count), .status_in(status_in),
        .ctrl_out(ctrl_out), .scratch_out(scratch_out)
    );

    initial begin
        repeat (2) @(posedge clk); @(negedge clk); rst = 0;

        // Seed SCRATCH = 0x1111_1111
        @(negedge clk); addr=8'h01; wr_data=32'h1111_1111; wr_en=1;
        @(negedge clk); wr_en=0;

        // Same-cycle read + write to SCRATCH: read should see OLD, store gets NEW
        @(negedge clk); addr=8'h01; wr_data=32'h2222_2222; wr_en=1; rd_en=1;
        @(posedge clk); @(negedge clk); wr_en=0; rd_en=0;
        #1;
        `CHECK_EQ(rd_data, 32'h1111_1111, "read-before-write returns old value")
        `CHECK_EQ(scratch_out, 32'h2222_2222, "write still applied (write wins)")

        // Back-to-back writes take effect in order
        @(negedge clk); addr=8'h02; wr_data=32'hAAAA_0000; wr_en=1;
        @(negedge clk); wr_data=32'hAAAA_FFFF;
        @(negedge clk); wr_en=0;
        `CHECK_EQ(ctrl_out, 32'hAAAA_FFFF, "last of back-to-back writes wins")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

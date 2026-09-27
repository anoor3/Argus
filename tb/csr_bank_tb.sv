// ============================================================================
// csr_bank_tb.sv -- self-checking testbench for csr_bank.sv
//
// Checks:
//   1. ID register reads the magic constant.
//   2. RW SCRATCH write then read returns written value.
//   3. RW CTRL write drives ctrl_out and reads back.
//   4. RO STATUS reflects status_in.
//   5. TIME_LO/TIME_HI reflect the 64-bit time_now split.
//   6. Write to an RO address is ignored (STATUS stays hardware-driven).
//   7. Reserved address reads 0.
//   8. Reset clears RW registers.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module csr_bank_tb;

    localparam int ADDRW = 8;
    localparam int DW    = 32;

    reg              clk = 0;
    reg              rst = 1;
    reg              wr_en = 0, rd_en = 0;
    reg  [ADDRW-1:0] addr = 0;
    reg  [DW-1:0]    wr_data = 0;
    wire [DW-1:0]    rd_data;
    wire             rd_valid;

    reg  [63:0]      time_now = 0;
    reg  [DW-1:0]    event_count = 0;
    reg  [DW-1:0]    status_in = 0;
    wire [DW-1:0]    ctrl_out, scratch_out;

    integer errors = 0;

    always #10 clk = ~clk;

    `WATCHDOG(200000)

    csr_bank #(.ADDRW(ADDRW), .DW(DW)) dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .rd_en(rd_en), .addr(addr),
        .wr_data(wr_data), .rd_data(rd_data), .rd_valid(rd_valid),
        .time_now(time_now), .event_count(event_count), .status_in(status_in),
        .ctrl_out(ctrl_out), .scratch_out(scratch_out)
    );

    // Issue a registered read. rd_en is asserted for exactly one clock; the
    // DUT presents rd_data + rd_valid on the following rising edge. We sample
    // just after that edge, while rd_valid is still high.
    task do_read(input [ADDRW-1:0] a);
        begin
            @(negedge clk); addr = a; rd_en = 1;
            @(posedge clk);            // DUT captures rd_en here
            @(negedge clk); rd_en = 0; // result now registered, rd_valid high
            #1;
        end
    endtask

    task do_write(input [ADDRW-1:0] a, input [DW-1:0] d);
        begin
            @(negedge clk); addr = a; wr_data = d; wr_en = 1;
            @(negedge clk); wr_en = 0;
        end
    endtask

    initial begin
        @(posedge clk); @(posedge clk);
        @(negedge clk); rst = 0;

        // ID
        do_read(8'h00);
        `CHECK_EQ(rd_data, 32'hA2_60_01_01, "ID register magic")
        `CHECK(rd_valid == 1'b1, "rd_valid asserts after read")

        // SCRATCH RW
        do_write(8'h01, 32'hDEAD_BEEF);
        `CHECK_EQ(scratch_out, 32'hDEAD_BEEF, "scratch_out reflects write")
        do_read(8'h01);
        `CHECK_EQ(rd_data, 32'hDEAD_BEEF, "SCRATCH readback")

        // CTRL RW
        do_write(8'h02, 32'h0000_0007);
        `CHECK_EQ(ctrl_out, 32'h0000_0007, "ctrl_out reflects write")
        do_read(8'h02);
        `CHECK_EQ(rd_data, 32'h0000_0007, "CTRL readback")

        // STATUS RO
        status_in = 32'h0000_00A5;
        do_read(8'h03);
        `CHECK_EQ(rd_data, 32'h0000_00A5, "STATUS reflects status_in")

        // TIME split
        time_now = 64'h1122_3344_5566_7788;
        do_read(8'h04);
        `CHECK_EQ(rd_data, 32'h5566_7788, "TIME_LO")
        do_read(8'h05);
        `CHECK_EQ(rd_data, 32'h1122_3344, "TIME_HI")

        // EVENT_COUNT RO
        event_count = 32'd42;
        do_read(8'h06);
        `CHECK_EQ(rd_data, 32'd42, "EVENT_COUNT reflects input")

        // Write to RO STATUS must be ignored: STATUS still returns status_in
        do_write(8'h03, 32'hFFFF_FFFF);
        status_in = 32'h0000_0011;
        do_read(8'h03);
        `CHECK_EQ(rd_data, 32'h0000_0011, "write to RO STATUS ignored")

        // Reserved address reads 0
        do_read(8'h7F);
        `CHECK_EQ(rd_data, 32'd0, "reserved addr reads 0")

        // Reset clears RW
        @(negedge clk); rst = 1;
        @(posedge clk); @(negedge clk); rst = 0;
        `CHECK_EQ(scratch_out, 32'd0, "reset clears SCRATCH")
        `CHECK_EQ(ctrl_out, 32'd0, "reset clears CTRL")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// test_sequencer_edge_tb.sv -- WAIT_EVENT timeout and unknown-op safety
//
// test_sequencer_tb covers the happy path and a READ_EXPECT mismatch. This
// adds:
//   1. WAIT_EVENT that never sees its event -> fails on timeout (no hang).
//   2. An unknown opcode -> fails safe with fail_pc captured.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_seq_ops.svh"
`include "argus_check.svh"

module test_sequencer_edge_tb;

    localparam int AW = 6;

    reg        clk = 0, rst = 1, start = 0;
    wire [AW-1:0] pc;
    reg  [47:0] mem [0:63];
    wire [47:0] instr = mem[pc];

    wire        csr_wr, csr_rd;
    wire [7:0]  csr_addr;
    wire [31:0] csr_wdata;
    reg  [31:0] csr_rdata = 0;
    reg         csr_rvalid = 0;
    reg         ev_valid = 0;
    reg  [7:0]  ev_code = 0;
    wire        inject_req;
    wire [7:0]  inject_mask;
    wire        busy, done, failed;
    wire [AW-1:0] fail_pc;

    integer errors = 0;

    always #10 clk = ~clk;
    `WATCHDOG(2000000)

    // small timeout so the test is fast
    test_sequencer #(.AW(AW), .WAIT_TIMEOUT(50)) dut (
        .clk(clk), .rst(rst), .start(start),
        .pc(pc), .instr(instr),
        .csr_wr(csr_wr), .csr_rd(csr_rd), .csr_addr(csr_addr),
        .csr_wdata(csr_wdata), .csr_rdata(csr_rdata), .csr_rvalid(csr_rvalid),
        .ev_valid(ev_valid), .ev_code(ev_code),
        .inject_req(inject_req), .inject_mask(inject_mask),
        .busy(busy), .done(done), .failed(failed), .fail_pc(fail_pc)
    );

    initial begin
        // 1. WAIT_EVENT that never fires -> timeout failure
        mem[0] = {`OP_WAIT_EVENT, 8'h55, 32'd0};   // wait for code 0x55 (never)
        mem[1] = {`OP_END, 8'd0, 32'd0};

        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (2) @(posedge clk);
        @(negedge clk); start=1; @(negedge clk); start=0;
        @(posedge done);
        `CHECK(failed == 1'b1, "WAIT_EVENT times out to failure")
        `CHECK_EQ(fail_pc, 0, "timeout fail_pc points at the WAIT_EVENT")

        // 2. Unknown opcode -> fail safe
        mem[0] = {8'hFE, 8'd0, 32'd0};   // not a real opcode
        mem[1] = {`OP_END, 8'd0, 32'd0};
        repeat (3) @(posedge clk);
        @(negedge clk); start=1; @(negedge clk); start=0;
        @(posedge done);
        `CHECK(failed == 1'b1, "unknown opcode fails safe")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

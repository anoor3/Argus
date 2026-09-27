// ============================================================================
// test_sequencer_tb.sv -- self-checking testbench for test_sequencer.sv
//
// Loads a small program into a behavioral memory and a simple CSR model, then
// checks:
//   1. WRITE then READ_EXPECT of the same value passes.
//   2. DELAY consumes cycles then continues.
//   3. INJECT raises inject_req/mask; CLEAR drops it.
//   4. WAIT_EVENT completes when a matching event arrives.
//   5. A READ_EXPECT mismatch sets failed with the correct fail_pc.
//   6. END sets done without failed on the good program.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_seq_ops.svh"
`include "argus_check.svh"

module test_sequencer_tb;

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

    test_sequencer #(.AW(AW), .WAIT_TIMEOUT(500)) dut (
        .clk(clk), .rst(rst), .start(start),
        .pc(pc), .instr(instr),
        .csr_wr(csr_wr), .csr_rd(csr_rd), .csr_addr(csr_addr),
        .csr_wdata(csr_wdata), .csr_rdata(csr_rdata), .csr_rvalid(csr_rvalid),
        .ev_valid(ev_valid), .ev_code(ev_code),
        .inject_req(inject_req), .inject_mask(inject_mask),
        .busy(busy), .done(done), .failed(failed), .fail_pc(fail_pc)
    );

    // Simple CSR model: 1 register at addr 0x01, registered read.
    reg [31:0] regfile;
    always @(posedge clk) begin
        if (rst) begin regfile<=0; csr_rvalid<=0; csr_rdata<=0; end
        else begin
            csr_rvalid <= csr_rd;
            if (csr_wr) regfile <= csr_wdata;
            if (csr_rd) csr_rdata <= regfile;
        end
    end

    task build_instr(input integer i, input [7:0] op, input [7:0] a, input [31:0] d);
        mem[i] = {op, a, d};
    endtask

    integer inject_seen = 0;
    always @(posedge clk) if (!rst && inject_req) inject_seen = inject_seen + 1;

    initial begin
        // ---- Good program ----
        build_instr(0, `OP_WRITE,       8'h01, 32'hABCD_0001);
        build_instr(1, `OP_READ_EXPECT, 8'h01, 32'hABCD_0001);
        build_instr(2, `OP_DELAY,       8'h00, 32'd5);
        build_instr(3, `OP_INJECT,      8'h00, 32'h0000_00F0);
        build_instr(4, `OP_WAIT_EVENT,  8'h21, 32'd0);   // wait CLK_OK code 0x21
        build_instr(5, `OP_CLEAR,       8'h00, 32'd0);
        build_instr(6, `OP_END,         8'h00, 32'd0);

        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (2) @(posedge clk);

        @(negedge clk); start = 1; @(negedge clk); start = 0;

        // While running, after some delay, fire the awaited event
        wait (inject_req == 1'b1);
        `CHECK_EQ(inject_mask, 8'hF0, "INJECT sets mask")
        repeat (5) @(posedge clk);
        @(negedge clk); ev_valid = 1; ev_code = 8'h21; @(negedge clk); ev_valid = 0;

        @(posedge done);
        `CHECK(failed == 1'b0, "good program passes")
        `CHECK(inject_seen > 0, "inject_req was asserted")
        `CHECK(inject_req == 1'b0, "CLEAR dropped inject_req before END")

        // ---- Failing program: READ_EXPECT mismatch at pc=1 ----
        build_instr(0, `OP_WRITE,       8'h01, 32'h1111_1111);
        build_instr(1, `OP_READ_EXPECT, 8'h01, 32'h2222_2222); // wrong
        build_instr(2, `OP_END,         8'h00, 32'd0);

        repeat (3) @(posedge clk);
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        @(posedge done);
        `CHECK(failed == 1'b1, "mismatch sets failed")
        `CHECK_EQ(fail_pc, 1, "fail_pc points at the READ_EXPECT")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

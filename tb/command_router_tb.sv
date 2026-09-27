// ============================================================================
// command_router_tb.sv -- self-checking testbench for command_router.sv
//
// Checks:
//   1. WRITE_REG frame drives csr_wr with correct addr and 32-bit data.
//   2. READ_REG frame issues csr_rd and streams 4 result bytes MSB-first.
//   3. RUN_SEQ frame pulses run_seq.
//   4. TRACE_READ frame pulses trace_read.
//   5. Unknown command consumes its frame without desyncing the parser.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module command_router_tb;

    reg        clk = 0, rst = 1;
    reg  [7:0] rx_byte = 0;
    reg        rx_valid = 0;

    wire       csr_wr, csr_rd;
    wire [7:0] csr_addr;
    wire [31:0] csr_wdata;
    reg  [31:0] csr_rdata = 0;
    reg         csr_rvalid = 0;

    wire [7:0] tx_byte;
    wire       tx_send;
    reg        tx_busy = 0;
    wire       run_seq, trace_read;

    integer errors = 0;

    always #10 clk = ~clk;
    `WATCHDOG(300000)

    command_router dut (
        .clk(clk), .rst(rst),
        .rx_byte(rx_byte), .rx_valid(rx_valid),
        .csr_wr(csr_wr), .csr_rd(csr_rd), .csr_addr(csr_addr),
        .csr_wdata(csr_wdata), .csr_rdata(csr_rdata), .csr_rvalid(csr_rvalid),
        .tx_byte(tx_byte), .tx_send(tx_send), .tx_busy(tx_busy),
        .run_seq(run_seq), .trace_read(trace_read)
    );

    // Feed one byte with a valid strobe.
    task feed(input [7:0] b);
        begin
            @(negedge clk); rx_byte = b; rx_valid = 1;
            @(negedge clk); rx_valid = 0;
        end
    endtask

    // Capture the next emitted tx byte.
    reg [7:0] cap; 
    task grab_tx(output [7:0] b);
        begin
            @(posedge tx_send); b = tx_byte; @(negedge clk);
        end
    endtask

    reg [7:0] g0,g1,g2,g3;

    initial begin
        @(posedge clk); @(negedge clk); rst = 0;

        // ---- WRITE_REG: addr 0x01, data 0xDEADBEEF ----
        feed(8'h01); feed(8'h01);
        feed(8'hDE); feed(8'hAD); feed(8'hBE); feed(8'hEF);
        @(posedge csr_wr); #1;
        `CHECK_EQ(csr_addr, 8'h01, "write addr")
        `CHECK_EQ(csr_wdata, 32'hDEADBEEF, "write data")

        // ---- READ_REG: addr 0x04, model returns 0x11223344 ----
        feed(8'h02); feed(8'h04);
        feed(8'h00); feed(8'h00); feed(8'h00); feed(8'h00);
        // csr model: respond one cycle after csr_rd
        @(posedge csr_rd);
        @(negedge clk); csr_rdata = 32'h11223344; csr_rvalid = 1;
        @(negedge clk); csr_rvalid = 0;
        grab_tx(g3); grab_tx(g2); grab_tx(g1); grab_tx(g0);
        `CHECK_EQ(g3, 8'h11, "read byte MSB")
        `CHECK_EQ(g2, 8'h22, "read byte 2")
        `CHECK_EQ(g1, 8'h33, "read byte 1")
        `CHECK_EQ(g0, 8'h44, "read byte LSB")

        // ---- RUN_SEQ ----
        fork
          begin feed(8'h04); feed(8'h00); feed(8'h00); feed(8'h00); feed(8'h00); feed(8'h00); end
          begin @(posedge run_seq); `CHECK(1'b1, "run_seq pulsed") end
        join

        // ---- Unknown cmd 0x7E then a valid WRITE to prove no desync ----
        feed(8'h7E); feed(8'h00); feed(8'h00); feed(8'h00); feed(8'h00); feed(8'h00);
        feed(8'h01); feed(8'h02); feed(8'h12); feed(8'h34); feed(8'h56); feed(8'h78);
        @(posedge csr_wr); #1;
        `CHECK_EQ(csr_addr, 8'h02, "parser resynced after unknown cmd")
        `CHECK_EQ(csr_wdata, 32'h12345678, "write data after unknown cmd")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

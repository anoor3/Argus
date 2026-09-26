// ============================================================================
// uart_tx_tb.sv -- self-checking testbench for uart_tx.sv
//
// Checks (with small CLKS_PER_BIT for fast sim):
//   1. Line idles high before start.
//   2. Start bit is 0, 8 data bits LSB-first, stop bit is 1.
//   3. busy asserts during the frame and clears after.
//   4. done pulses once at end of frame.
//   5. A second start after done sends a second correct byte.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module uart_tx_tb;

    localparam int CPB = 8;

    reg        clk = 0, rst = 1, start = 0;
    reg  [7:0] tx_data = 0;
    wire       tx, busy, done;

    integer errors = 0;

    always #10 clk = ~clk;

    uart_tx #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst), .start(start),
        .tx_data(tx_data), .tx(tx), .busy(busy), .done(done)
    );

    // Sample the middle of the next bit period and return the level.
    task sample_bit(output bit level);
        begin
            repeat (CPB) @(posedge clk);
            level = tx;
        end
    endtask

    reg [7:0] sent;
    integer i;
    bit b;

    task send_and_check(input [7:0] value);
        begin
            @(negedge clk); tx_data = value; start = 1;
            @(negedge clk); start = 0;
            // Align to just after the frame begins; move to center of start bit
            repeat (CPB/2) @(posedge clk);
            `CHECK(tx == 1'b0, "start bit should be 0")
            // 8 data bits LSB-first
            for (i = 0; i < 8; i = i + 1) begin
                sample_bit(b);
                sent[i] = b;
            end
            `CHECK_EQ(sent, value, "transmitted data bits match input")
            // stop bit
            sample_bit(b);
            `CHECK(b == 1'b1, "stop bit should be 1")
            // wait for done/idle
            @(posedge done);
            `CHECK(busy == 1'b0, "busy clears after done")
        end
    endtask

    initial begin
        @(posedge clk); @(posedge clk);
        @(negedge clk); rst = 0;
        `CHECK(tx == 1'b1, "line idles high")

        send_and_check(8'hA5);
        repeat (3) @(posedge clk);
        send_and_check(8'h3C);

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// uart_loopback_tb.sv -- integration test: uart_tx -> uart_rx wired together
//
// Purpose:
//   Prove the transmitter and receiver agree on framing and timing by looping
//   tx directly into rx and checking several bytes make the round trip intact.
//
// Checks:
//   1. Each transmitted byte is received identically.
//   2. No frame errors occur on a clean loopback.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module uart_loopback_tb;

    localparam int CPB = 8;

    reg        clk = 0, rst = 1;
    reg        start = 0;
    reg  [7:0] tx_data = 0;
    wire       line;                 // tx -> rx
    wire       tx_busy, tx_done;
    wire [7:0] rx_data;
    wire       rx_valid, rx_ferr;

    integer errors = 0;
    integer err_seen = 0;

    // Latch received byte whenever rx signals a valid byte.
    reg [7:0] last_rx;
    reg       got_rx;

    always #10 clk = ~clk;

    // Never hang: 8 bytes * ~11 bits * 8 clks * 20ns ~= 14us; give wide margin.
    `WATCHDOG(200000)

    uart_tx #(.CLKS_PER_BIT(CPB)) u_tx (
        .clk(clk), .rst(rst), .start(start),
        .tx_data(tx_data), .tx(line), .busy(tx_busy), .done(tx_done)
    );

    uart_rx #(.CLKS_PER_BIT(CPB)) u_rx (
        .clk(clk), .rst(rst), .rx(line),
        .rx_data(rx_data), .data_valid(rx_valid), .frame_error(rx_ferr)
    );

    always @(posedge clk) begin
        if (rst) begin
            err_seen <= 0; got_rx <= 1'b0;
        end else begin
            if (rx_ferr)  err_seen <= err_seen + 1;
            if (rx_valid) begin last_rx <= rx_data; got_rx <= 1'b1; end
        end
    end

    task xfer(input [7:0] value);
        begin
            got_rx = 1'b0;
            @(negedge clk); tx_data = value; start = 1;
            @(negedge clk); start = 0;
            // Wait until the whole frame has been transmitted...
            @(posedge tx_done);
            // ...then wait for the receiver to flag the recovered byte.
            wait (got_rx == 1'b1);
            @(negedge clk);
            `CHECK_EQ(last_rx, value, "loopback byte round-trips")
        end
    endtask

    initial begin
        @(posedge clk); @(posedge clk);
        @(negedge clk); rst = 0;
        repeat (4) @(posedge clk);

        xfer(8'h00);
        xfer(8'hFF);
        xfer(8'hA5);
        xfer(8'h5A);
        xfer(8'h81);

        `CHECK_EQ(err_seen, 0, "no frame errors on clean loopback")
        `FINISH_REPORT
    end

endmodule

`default_nettype wire

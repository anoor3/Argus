// ============================================================================
// spi_master_tb.sv -- self-checking testbench for spi_master.sv (mode 0)
//
// A behavioral SPI slave model shifts out a known response byte on MISO while
// capturing MOSI, sampling/driving on the standard mode-0 edges. We check:
//   1. The master receives the slave's response byte on rx_byte.
//   2. The slave receives the master's tx_byte (MOSI path correct).
//   3. busy/done behave and cs_n frames the transfer.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module spi_master_tb;

    reg        clk = 0, rst = 1, start = 0;
    reg        cpol = 0, cpha = 0;
    reg  [7:0] clk_div = 8'd1;
    reg  [7:0] tx_byte = 8'hA5;
    wire       sclk, mosi, cs_n;
    reg        miso = 0;
    wire [7:0] rx_byte;
    wire       busy, done;

    integer errors = 0;

    always #10 clk = ~clk;
    `WATCHDOG(600000)

    spi_master dut (
        .clk(clk), .rst(rst), .start(start),
        .cpol(cpol), .cpha(cpha), .clk_div(clk_div),
        .tx_byte(tx_byte), .miso(miso),
        .sclk(sclk), .mosi(mosi), .cs_n(cs_n),
        .rx_byte(rx_byte), .busy(busy), .done(done)
    );

    // ---- Mode-0 slave model ----
    // CPHA=0: master samples on rising SCLK, drives on falling.
    // Slave: drive MISO on falling edge (present bit before rising), sample
    // MOSI on rising edge. Sends SLAVE_RESP MSB-first.
    localparam [7:0] SLAVE_RESP = 8'h3C;
    reg [7:0] slv_tx, slv_rx;
    integer   slv_bits;

    always @(negedge cs_n) begin
        slv_tx   = SLAVE_RESP;
        slv_rx   = 8'd0;
        slv_bits = 0;
        miso     = SLAVE_RESP[7]; // present MSB while cs asserts
    end

    // Sample MOSI on rising SCLK
    always @(posedge sclk) if (!cs_n) begin
        slv_rx  = {slv_rx[6:0], mosi};
        slv_bits = slv_bits + 1;
    end
    // Drive next MISO bit on falling SCLK
    always @(negedge sclk) if (!cs_n) begin
        slv_tx = {slv_tx[6:0], 1'b0};
        miso   = slv_tx[7];
    end

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        @(negedge clk); tx_byte = 8'hA5; start = 1;
        @(negedge clk); start = 0;

        `CHECK(busy == 1'b1, "busy asserts during transfer")
        @(posedge done);
        `CHECK_EQ(rx_byte, SLAVE_RESP, "master received slave response byte")
        `CHECK_EQ(slv_rx, 8'hA5, "slave received master tx byte")
        `CHECK(cs_n == 1'b1, "cs_n deasserts after transfer")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// spi_master_edge_tb.sv -- SPI mode 1 (CPOL=0, CPHA=1) coverage
//
// spi_master_tb covers mode 0. This exercises CPHA=1, where the master drives
// on the leading edge and samples on the trailing edge, against a matching
// slave model. Confirms the mode bit actually changes the sampling edge.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module spi_master_edge_tb;

    reg        clk = 0, rst = 1, start = 0;
    reg        cpol = 0, cpha = 1;      // mode 1
    reg  [7:0] clk_div = 8'd1;
    reg  [7:0] tx_byte = 8'h6D;
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

    // Mode-1 slave: master samples MISO on trailing (falling) SCLK, so present
    // the next MISO bit on the leading (rising) edge. Sample MOSI on falling.
    localparam [7:0] SLAVE_RESP = 8'hE1;
    reg [7:0] slv_tx, slv_rx;

    always @(negedge cs_n) begin
        slv_tx = SLAVE_RESP;
        slv_rx = 8'd0;
        // In CPHA=1 the first MISO bit is presented on the first leading edge.
    end
    always @(posedge sclk) if (!cs_n) begin
        miso   = slv_tx[7];
        slv_tx = {slv_tx[6:0], 1'b0};
    end
    always @(negedge sclk) if (!cs_n) begin
        slv_rx = {slv_rx[6:0], mosi};
    end

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        @(negedge clk); tx_byte = 8'h6D; start = 1;
        @(negedge clk); start = 0;
        @(posedge done);
        `CHECK_EQ(rx_byte, SLAVE_RESP, "mode-1 master received slave byte")
        `CHECK_EQ(slv_rx, 8'h6D, "mode-1 slave received master byte")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// adc_bridge_tb.sv -- unit test for adc_bridge.sv using a deterministic SPI stub
//
// The stub completes each SPI transfer in a fixed number of cycles and returns
// a programmed byte per transfer, so this test isolates the adc_bridge FSM and
// sample-assembly logic from SPI bit-timing (which spi_master_tb already
// covers). Checks:
//   1. Two transfers occur and the 12-bit sample is assembled as {hi[3:0],lo}.
//   2. valid pulses exactly once; busy frames the read.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module adc_bridge_tb;

    reg        clk = 0, rst = 1, start = 0;

    wire        spi_start;
    wire [7:0]  spi_tx_byte;
    reg         spi_done = 0;
    reg  [7:0]  spi_rx_byte = 0;
    reg         spi_busy = 0;

    wire [15:0] sample;
    wire        valid, busy;

    integer errors = 0;
    integer valid_cnt = 0;

    always #10 clk = ~clk;
    `WATCHDOG(1000000)

    adc_bridge #(.CMD_BYTE(8'h01)) uut (
        .clk(clk), .rst(rst), .start(start),
        .spi_start(spi_start), .spi_tx_byte(spi_tx_byte),
        .spi_done(spi_done), .spi_rx_byte(spi_rx_byte), .spi_busy(spi_busy),
        .sample(sample), .valid(valid), .busy(busy)
    );

    // ---- deterministic SPI stub (single always, counter based) ----
    // On spi_start, count down; when it hits zero, present resp[idx] and pulse
    // spi_done for one cycle.
    reg [7:0]  resp [0:1];
    integer    idx = 0;
    integer    cd = 0;          // countdown; 0 = idle
    initial begin resp[0]=8'h0A; resp[1]=8'h5C; end

    always @(posedge clk) begin
        if (rst) begin
            spi_done <= 1'b0; spi_busy <= 1'b0; spi_rx_byte <= 8'd0;
            idx <= 0; cd <= 0;
        end else begin
            spi_done <= 1'b0;
            if (spi_start && cd == 0) begin
                spi_busy <= 1'b1;
                cd       <= 5;             // transfer takes 5 cycles
            end else if (cd > 1) begin
                cd <= cd - 1;
            end else if (cd == 1) begin
                spi_rx_byte <= resp[idx];
                spi_done    <= 1'b1;
                spi_busy    <= 1'b0;
                cd          <= 0;
                if (idx < 1) idx <= idx + 1;
            end
        end
    end

    always @(posedge clk) if (!rst && valid) valid_cnt = valid_cnt + 1;

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (3) @(posedge clk);

        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        `CHECK(busy == 1'b1, "busy during ADC read")

        @(posedge valid);
        `CHECK_EQ(sample, 16'h0A5C, "assembled 12-bit sample {hi[3:0],lo}")

        repeat (3) @(posedge clk);
        `CHECK_EQ(valid_cnt, 1, "valid pulses once")
        `CHECK(busy == 1'b0, "busy clears after read")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

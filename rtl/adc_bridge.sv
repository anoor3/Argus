// ============================================================================
// adc_bridge.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Reads a sensor sample (voltage/current/temperature) from an external ADC or
//   sensor IC *over SPI*, never by connecting analog directly to FPGA pins
//   (see docs/SAFETY.md). It sequences the two SPI byte transfers of a typical
//   12-bit ADC read and assembles the result.
//
// Interface:
//   clk, rst              : clock / sync reset
//   start                 : begin one sample read
//   -- to spi_master --
//   spi_start             : pulse to launch a byte transfer
//   spi_tx_byte[7:0]      : byte to send for this transfer
//   spi_done              : transfer complete
//   spi_rx_byte[7:0]      : byte received
//   spi_busy              : master busy
//   -- result --
//   sample[15:0]          : assembled 12-bit sample (right-aligned)
//   valid                 : 1-cycle pulse when sample is ready
//   busy                  : high during a read
//
// Sequence: send command byte, capture high nibble+byte, send dummy, capture
//   low byte, assemble {hi[3:0], lo[7:0]} = 12 bits. The command byte is a
//   parameter so different sensors can be targeted.
//
// Edge/error cases:
//   - start while busy: ignored.
//   - reset mid-read: returns to idle, no spurious valid.
//
// Design tradeoff:
//   Driving the shared spi_master (vs. embedding another SPI engine) keeps one
//   verified SPI implementation and enforces the "sensor via digital bus" rule.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module adc_bridge #(
    parameter [7:0] CMD_BYTE = 8'h01
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    output reg         spi_start,
    output reg  [7:0]  spi_tx_byte,
    input  wire        spi_done,
    input  wire [7:0]  spi_rx_byte,
    input  wire        spi_busy,

    output reg  [15:0] sample,
    output reg         valid,
    output reg         busy
);

    localparam [2:0] S_IDLE=0, S_CMD=1, S_HI=2, S_LO=3, S_ASM=4;

    reg [2:0] state;
    reg [7:0] hi, lo;

    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; spi_start<=1'b0; spi_tx_byte<=8'd0;
            sample<=16'd0; valid<=1'b0; busy<=1'b0; hi<=0; lo<=0;
        end else begin
            spi_start <= 1'b0;
            valid     <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        spi_tx_byte <= CMD_BYTE;
                        spi_start   <= 1'b1;
                        state       <= S_CMD;
                    end
                end
                S_CMD: if (spi_done) begin
                    hi          <= spi_rx_byte;  // first returned byte
                    spi_tx_byte <= 8'h00;        // dummy for second byte
                    spi_start   <= 1'b1;
                    state       <= S_LO;
                end
                S_LO: if (spi_done) begin
                    lo    <= spi_rx_byte;
                    state <= S_ASM;
                end
                S_ASM: begin
                    // assemble 12-bit sample: low nibble of hi + full lo
                    sample <= {4'd0, hi[3:0], lo};
                    valid  <= 1'b1;
                    busy   <= 1'b0;
                    state  <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

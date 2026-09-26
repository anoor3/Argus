// ============================================================================
// uart_tx.sv
// ----------------------------------------------------------------------------
// Purpose:
//   8-N-1 UART transmitter. Serializes one byte at a time onto `tx` at a baud
//   rate set by CLKS_PER_BIT. This is the DUT/host serial output path.
//
// Interface:
//   clk, rst          : clock / synchronous active-high reset
//   start             : pulse to begin sending tx_data (ignored while busy)
//   tx_data[7:0]      : byte to send, sampled when start is accepted
//   tx                : serial line (idle high)
//   busy              : high from acceptance until the stop bit completes
//   done              : 1-cycle pulse when the stop bit finishes
//
// Framing (8-N-1): idle high -> start bit (0) -> 8 data bits LSB-first ->
//   stop bit (1) -> idle high. Each bit lasts CLKS_PER_BIT clocks.
//
// State machine: IDLE -> START -> DATA(x8) -> STOP -> IDLE.
//
// Edge/error cases:
//   - start asserted while busy: ignored (current frame is not corrupted).
//   - reset mid-frame: line returns to idle high, busy clears.
//
// Design tradeoff:
//   Parameterized CLKS_PER_BIT (vs. fixed baud) lets the same RTL retarget any
//   clock/baud combo and lets the TB use a tiny divisor for fast simulation.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module uart_tx #(
    parameter int CLKS_PER_BIT = 434  // 50 MHz / 115200
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [7:0]  tx_data,
    output reg         tx,
    output reg         busy,
    output reg         done
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    wire bit_done = (clk_cnt == CLKS_PER_BIT-1);

    always @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            tx      <= 1'b1;   // idle high
            busy    <= 1'b0;
            done    <= 1'b0;
            clk_cnt <= 16'd0;
            bit_idx <= 3'd0;
            shreg   <= 8'd0;
        end else begin
            done <= 1'b0;      // default: single-cycle pulse
            case (state)
                S_IDLE: begin
                    tx   <= 1'b1;
                    busy <= 1'b0;
                    if (start) begin
                        busy    <= 1'b1;
                        shreg   <= tx_data;
                        clk_cnt <= 16'd0;
                        state   <= S_START;
                    end
                end
                S_START: begin
                    tx <= 1'b0; // start bit
                    if (bit_done) begin
                        clk_cnt <= 16'd0;
                        bit_idx <= 3'd0;
                        state   <= S_DATA;
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
                S_DATA: begin
                    tx <= shreg[bit_idx];
                    if (bit_done) begin
                        clk_cnt <= 16'd0;
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 1'b1;
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
                S_STOP: begin
                    tx <= 1'b1; // stop bit
                    if (bit_done) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

// ============================================================================
// uart_rx.sv
// ----------------------------------------------------------------------------
// Purpose:
//   8-N-1 UART receiver. Recovers one byte from the serial `rx` line, sampling
//   each bit at its center for noise margin. This is the host/DUT serial input.
//
// Interface:
//   clk, rst          : clock / synchronous active-high reset
//   rx                : serial input (idle high); double-flopped internally
//   rx_data[7:0]      : recovered byte, valid when data_valid pulses
//   data_valid        : 1-cycle pulse when a byte is fully received
//   frame_error       : 1-cycle pulse if the stop bit was not high (framing err)
//
// Bit recovery: detect start-bit falling edge, wait half a bit to reach the
//   center, then sample every CLKS_PER_BIT at bit centers for 8 data bits,
//   then check the stop bit is high.
//
// State machine: IDLE -> START -> DATA(x8) -> STOP -> IDLE.
//
// Edge/error cases:
//   - Metastability on rx: the raw line is passed through 2 flip-flops before
//     use (async input -> sync domain), per the CDC rule in the requirements.
//   - False start (rx returns high before center): rejected, back to IDLE.
//   - Bad stop bit: frame_error pulses; data_valid still marks the byte so the
//     host can decide, but the error is recorded (defined behavior).
//
// Design tradeoff:
//   Center-sampling (vs. sampling at the edge) maximizes tolerance to baud
//   mismatch and edge jitter. Cost is a half-bit counter and one extra state.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module uart_rx #(
    parameter int CLKS_PER_BIT = 434
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        rx,
    output reg  [7:0]  rx_data,
    output reg         data_valid,
    output reg         frame_error
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    // Two-flop synchronizer for the asynchronous rx line.
    reg rx_meta, rx_sync;
    always @(posedge clk) begin
        if (rst) begin rx_meta <= 1'b1; rx_sync <= 1'b1; end
        else     begin rx_meta <= rx;   rx_sync <= rx_meta; end
    end

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shreg;

    always @(posedge clk) begin
        if (rst) begin
            state       <= S_IDLE;
            clk_cnt     <= 16'd0;
            bit_idx     <= 3'd0;
            shreg       <= 8'd0;
            rx_data     <= 8'd0;
            data_valid  <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            data_valid  <= 1'b0;   // single-cycle pulses
            frame_error <= 1'b0;
            case (state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (rx_sync == 1'b0) state <= S_START; // start edge
                end
                S_START: begin
                    // Wait to the center of the start bit.
                    if (clk_cnt == (CLKS_PER_BIT-1)/2) begin
                        if (rx_sync == 1'b0) begin
                            clk_cnt <= 16'd0;
                            state   <= S_DATA;
                        end else begin
                            state <= S_IDLE; // false start
                        end
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt         <= 16'd0;
                        shreg[bit_idx]  <= rx_sync;   // sample at center
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 1'b1;
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        rx_data     <= shreg;
                        data_valid  <= 1'b1;
                        frame_error <= (rx_sync != 1'b1); // stop must be high
                        state       <= S_IDLE;
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

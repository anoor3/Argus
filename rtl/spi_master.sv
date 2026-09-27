// ============================================================================
// spi_master.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Configurable SPI master that shifts out one byte on MOSI while capturing
//   one byte on MISO, with programmable clock divider and CPOL/CPHA mode. Used
//   to script transactions to an SPI DUT/peripheral and check the response.
//
// Interface:
//   clk, rst          : clock / sync reset
//   start             : pulse to begin a transfer (ignored while busy)
//   cpol, cpha        : SPI mode bits
//   clk_div[7:0]      : SCLK half-period = (clk_div+1) system clocks
//   tx_byte[7:0]      : byte to send (MSB first)
//   miso              : serial input from peripheral
//   sclk, mosi, cs_n  : SPI outputs (cs_n active low, asserted during transfer)
//   rx_byte[7:0]      : captured byte
//   busy, done        : status / 1-cycle completion pulse
//
// Framing: cs_n low, then 8 SCLK pulses. Data is driven on the "drive" edge and
//   sampled on the "sample" edge, selected by CPOL/CPHA. MSB first.
//
// Edge/error cases:
//   - start while busy: ignored.
//   - reset mid-transfer: outputs return to idle (cs_n high, sclk = cpol).
//
// Design tradeoff:
//   A single shift path with mode-selected edges (vs. four hard-coded modes)
//   keeps the RTL compact and lets the TB sweep modes.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module spi_master (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire        cpol,
    input  wire        cpha,
    input  wire [7:0]  clk_div,
    input  wire [7:0]  tx_byte,
    input  wire        miso,
    output reg         sclk,
    output reg         mosi,
    output reg         cs_n,
    output reg  [7:0]  rx_byte,
    output reg         busy,
    output reg         done
);

    localparam [1:0] S_IDLE=2'd0, S_ASSERT=2'd1, S_XFER=2'd2, S_DONE=2'd3;

    reg [1:0]  state;
    reg [7:0]  div_cnt;
    reg [3:0]  edge_cnt;   // 16 edges = 8 bits
    reg [7:0]  shift_tx, shift_rx;
    reg        sclk_int;

    wire tick = (div_cnt == clk_div);

    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; sclk<=cpol; sclk_int<=cpol; mosi<=1'b0; cs_n<=1'b1;
            rx_byte<=8'd0; busy<=1'b0; done<=1'b0;
            div_cnt<=8'd0; edge_cnt<=4'd0; shift_tx<=8'd0; shift_rx<=8'd0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    sclk <= cpol; sclk_int <= cpol; cs_n <= 1'b1; busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        shift_tx <= tx_byte;
                        shift_rx <= 8'd0;
                        div_cnt  <= 8'd0;
                        edge_cnt <= 4'd0;
                        cs_n     <= 1'b0;
                        // For CPHA=0, first data bit must be presented before
                        // the first sampling edge.
                        mosi     <= tx_byte[7];
                        state    <= S_ASSERT;
                    end
                end
                S_ASSERT: begin
                    // one divider period of cs setup, then start toggling
                    if (tick) begin div_cnt<=8'd0; state<=S_XFER; end
                    else div_cnt <= div_cnt + 1'b1;
                end
                S_XFER: begin
                    if (tick) begin
                        div_cnt  <= 8'd0;
                        sclk_int <= ~sclk_int;
                        sclk     <= ~sclk_int;
                        // Determine sample vs drive edge from cpha.
                        // leading edge = first toggle after assert.
                        // even edge_cnt -> leading, odd -> trailing.
                        if (cpha == 1'b0) begin
                            if (edge_cnt[0] == 1'b0) begin
                                // leading edge: sample
                                shift_rx <= {shift_rx[6:0], miso};
                            end else begin
                                // trailing edge: drive next bit
                                shift_tx <= {shift_tx[6:0], 1'b0};
                                mosi     <= shift_tx[6];
                            end
                        end else begin
                            if (edge_cnt[0] == 1'b0) begin
                                // leading edge: drive
                                mosi     <= shift_tx[7];
                                shift_tx <= {shift_tx[6:0], 1'b0};
                            end else begin
                                // trailing edge: sample
                                shift_rx <= {shift_rx[6:0], miso};
                            end
                        end
                        if (edge_cnt == 4'd15) begin
                            state   <= S_DONE;
                        end else begin
                            edge_cnt <= edge_cnt + 1'b1;
                        end
                    end else div_cnt <= div_cnt + 1'b1;
                end
                S_DONE: begin
                    sclk    <= cpol; sclk_int <= cpol;
                    cs_n    <= 1'b1;
                    rx_byte <= shift_rx;
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    state   <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

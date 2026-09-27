// ============================================================================
// command_router.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Decodes fixed-length host command frames arriving as UART bytes and turns
//   them into CSR reads/writes, trace reads, or sequencer starts. For read
//   commands it streams the 32-bit result back out as 4 bytes.
//
// Frame (see docs/REQUIREMENTS.md):
//   [CMD][ADDR][DATA3][DATA2][DATA1][DATA0]   (DATA big-endian, MSB first)
//   CMD: 0x01 WRITE_REG, 0x02 READ_REG, 0x03 TRACE_READ, 0x04 RUN_SEQ
//
// Interface:
//   clk, rst              : clock / sync active-high reset
//   rx_byte[7:0], rx_valid: one received byte from uart_rx
//   -- CSR port --
//   csr_wr, csr_rd        : one-cycle strobes to csr_bank
//   csr_addr[7:0]         : register address
//   csr_wdata[31:0]       : write data
//   csr_rdata[31:0]       : read data from csr_bank
//   csr_rvalid            : csr read result strobe
//   -- outputs to tx --
//   tx_byte[7:0], tx_send : byte + strobe to uart_tx (host must be idle)
//   tx_busy               : uart_tx busy (backpressure)
//   -- misc --
//   run_seq               : one-cycle pulse on RUN_SEQ command
//   trace_read            : one-cycle pulse on TRACE_READ command
//
// State machine: collects 6 bytes (GET_CMD..GET_D0), then ACTs. For reads it
//   enters SEND_x states, emitting one byte when tx is not busy.
//
// Edge/error cases:
//   - Unknown CMD: frame is still consumed (6 bytes) then dropped, no action,
//     so a bad byte cannot desync the parser forever.
//   - tx busy during response: router waits (no byte dropped).
//
// Design tradeoff:
//   Fixed-length frames (vs. variable/length-prefixed) make the parser a simple
//   counter FSM with no buffering, which is easy to verify exhaustively.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module command_router (
    input  wire        clk,
    input  wire        rst,

    input  wire [7:0]  rx_byte,
    input  wire        rx_valid,

    output reg         csr_wr,
    output reg         csr_rd,
    output reg  [7:0]  csr_addr,
    output reg  [31:0] csr_wdata,
    input  wire [31:0] csr_rdata,
    input  wire        csr_rvalid,

    output reg  [7:0]  tx_byte,
    output reg         tx_send,
    input  wire        tx_busy,

    output reg         run_seq,
    output reg         trace_read
);

    localparam [7:0] CMD_WRITE = 8'h01,
                     CMD_READ  = 8'h02,
                     CMD_TRACE = 8'h03,
                     CMD_RUNSEQ= 8'h04;

    localparam [3:0] S_CMD   = 4'd0,
                     S_ADDR  = 4'd1,
                     S_D3    = 4'd2,
                     S_D2    = 4'd3,
                     S_D1    = 4'd4,
                     S_D0    = 4'd5,
                     S_ACT   = 4'd6,
                     S_RWAIT = 4'd7,  // wait for csr read data
                     S_S3    = 4'd8,  // send bytes MSB..LSB
                     S_S2    = 4'd9,
                     S_S1    = 4'd10,
                     S_S0    = 4'd11;

    reg [3:0]  state;
    reg [7:0]  cmd;
    reg [31:0] data;
    reg [31:0] rdata_lat;

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_CMD;
            csr_wr     <= 1'b0; csr_rd <= 1'b0;
            csr_addr   <= 8'd0; csr_wdata <= 32'd0;
            tx_byte    <= 8'd0; tx_send <= 1'b0;
            run_seq    <= 1'b0; trace_read <= 1'b0;
            cmd        <= 8'd0; data <= 32'd0; rdata_lat <= 32'd0;
        end else begin
            // default one-cycle strobes
            csr_wr <= 1'b0; csr_rd <= 1'b0;
            tx_send <= 1'b0; run_seq <= 1'b0; trace_read <= 1'b0;

            case (state)
                S_CMD:  if (rx_valid) begin cmd <= rx_byte; state <= S_ADDR; end
                S_ADDR: if (rx_valid) begin csr_addr <= rx_byte; state <= S_D3; end
                S_D3:   if (rx_valid) begin data[31:24] <= rx_byte; state <= S_D2; end
                S_D2:   if (rx_valid) begin data[23:16] <= rx_byte; state <= S_D1; end
                S_D1:   if (rx_valid) begin data[15:8]  <= rx_byte; state <= S_D0; end
                S_D0:   if (rx_valid) begin data[7:0]   <= rx_byte; state <= S_ACT; end

                S_ACT: begin
                    case (cmd)
                        CMD_WRITE: begin
                            csr_wdata <= data;
                            csr_wr    <= 1'b1;
                            state     <= S_CMD;
                        end
                        CMD_READ: begin
                            csr_rd <= 1'b1;
                            state  <= S_RWAIT;
                        end
                        CMD_TRACE: begin
                            trace_read <= 1'b1;
                            csr_rd     <= 1'b1;      // TRACE_RDATA is a CSR too
                            state      <= S_RWAIT;
                        end
                        CMD_RUNSEQ: begin
                            run_seq <= 1'b1;
                            state   <= S_CMD;
                        end
                        default: state <= S_CMD; // unknown: drop
                    endcase
                end

                S_RWAIT: if (csr_rvalid) begin
                    rdata_lat <= csr_rdata;
                    state     <= S_S3;
                end

                S_S3: if (!tx_busy) begin tx_byte <= rdata_lat[31:24]; tx_send <= 1'b1; state <= S_S2; end
                S_S2: if (!tx_busy && !tx_send) begin tx_byte <= rdata_lat[23:16]; tx_send <= 1'b1; state <= S_S1; end
                S_S1: if (!tx_busy && !tx_send) begin tx_byte <= rdata_lat[15:8];  tx_send <= 1'b1; state <= S_S0; end
                S_S0: if (!tx_busy && !tx_send) begin tx_byte <= rdata_lat[7:0];   tx_send <= 1'b1; state <= S_CMD; end

                default: state <= S_CMD;
            endcase
        end
    end

endmodule

`default_nettype wire

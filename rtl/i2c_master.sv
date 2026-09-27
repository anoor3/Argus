// ============================================================================
// i2c_master.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Minimal single-byte I2C master: generates START, sends a 7-bit address +
//   R/W bit, transfers one data byte, checks ACK/NACK, and issues STOP. Used to
//   script I2C transactions to a DUT/sensor and report ACK/NACK/timeout.
//
// Electrical model (simulation):
//   I2C is open-drain: a device pulls low or releases (pulled high). We model
//   this with separate drive-enable + value. sda_oe/scl_oe high means the
//   master pulls the line low (line = 0); when low the line is released (the
//   testbench/slave provides the level via sda_in/scl_in with pull-ups).
//
// Interface:
//   clk, rst           : clock / sync reset
//   start              : begin a transaction
//   addr[6:0], rw      : 7-bit address, rw (0=write here)
//   wr_byte[7:0]       : data byte to write
//   clk_div[15:0]      : SCL quarter-period in system clocks
//   sda_in, scl_in     : sampled bus levels (with pull-ups in the TB)
//   sda_oe, scl_oe     : master drive-low enables
//   rd_byte[7:0]       : (reserved for read path; 0 for write-only here)
//   ack                : 1 if slave ACKed the address/data
//   busy, done         : status / completion
//
// State machine: IDLE->START->ADDR(8)->ADDR_ACK->DATA(8)->DATA_ACK->STOP.
//   SCL is generated in quarter phases so SDA changes while SCL is low and is
//   stable while SCL is high (I2C rule).
//
// Edge/error cases:
//   - NACK on address: ack=0, transaction still terminates with STOP (no hang).
//   - reset mid-transfer: bus released (both oe low), busy clears.
//
// Design tradeoff:
//   Quarter-phase SCL generation (vs. half) makes the "change SDA while SCL
//   low, sample while high" rule explicit and easy to verify.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module i2c_master (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [6:0]  addr,
    input  wire        rw,
    input  wire [7:0]  wr_byte,
    input  wire [15:0] clk_div,
    input  wire        sda_in,
    input  wire        scl_in,
    output reg         sda_oe,
    output reg         scl_oe,
    output reg  [7:0]  rd_byte,
    output reg         ack,
    output reg         busy,
    output reg         done
);

    localparam [3:0] S_IDLE=0, S_START=1, S_ADDR=2, S_AACK=3,
                     S_DATA=4, S_DACK=5, S_STOP=6, S_DONE=7;

    reg [3:0]  state;
    reg [15:0] qcnt;      // quarter-phase counter
    reg [1:0]  phase;     // 0..3 within a bit
    reg [3:0]  bit_idx;
    reg [8:0]  shifter;   // 8 bits + we shift MSB first

    wire qtick = (qcnt == clk_div);

    // Convenience: drive SDA low (oe=1) or release (oe=0).
    task set_sda(input bit low); sda_oe = low; endtask

    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; sda_oe<=1'b0; scl_oe<=1'b0; ack<=1'b0;
            busy<=1'b0; done<=1'b0; qcnt<=0; phase<=0; bit_idx<=0;
            shifter<=9'd0; rd_byte<=8'd0;
        end else begin
            done <= 1'b0;
            if (state != S_IDLE && !qtick) qcnt <= qcnt + 1'b1;
            else qcnt <= 16'd0;

            case (state)
                S_IDLE: begin
                    sda_oe<=1'b0; scl_oe<=1'b0; busy<=1'b0;
                    if (start) begin
                        busy    <= 1'b1;
                        shifter <= {addr, rw, 1'b0}; // 8 payload bits in [8:1], drive [8]
                        bit_idx <= 4'd0;
                        phase   <= 2'd0;
                        // START: SDA high->low while SCL high
                        sda_oe  <= 1'b0;  // release (high)
                        scl_oe  <= 1'b0;  // release (high)
                        state   <= S_START;
                    end
                end
                S_START: if (qtick) begin
                    phase <= phase + 1'b1;
                    case (phase)
                        2'd0: sda_oe <= 1'b1;         // pull SDA low (start)
                        2'd1: scl_oe <= 1'b1;         // then SCL low
                        2'd3: begin state <= S_ADDR; phase<=0; bit_idx<=0; end
                        default: ;
                    endcase
                end
                S_ADDR: if (qtick) begin
                    phase <= phase + 1'b1;
                    case (phase)
                        2'd0: sda_oe <= ~shifter[8] ? 1'b1:1'b0; // drive MSB while SCL low
                        2'd1: scl_oe <= 1'b0;  // release SCL high (data stable)
                        2'd3: begin
                            scl_oe  <= 1'b1;    // SCL low again
                            shifter <= {shifter[7:0], 1'b0}; // next bit to MSB
                            if (bit_idx == 4'd7) begin state<=S_AACK; phase<=0; end
                            else bit_idx <= bit_idx + 1'b1;
                        end
                        default: ;
                    endcase
                end
                S_AACK: if (qtick) begin
                    phase <= phase + 1'b1;
                    case (phase)
                        2'd0: sda_oe <= 1'b0;  // release SDA for slave ACK
                        2'd1: scl_oe <= 1'b0;  // SCL high
                        2'd2: ack    <= ~sda_in; // ACK = slave pulled low
                        2'd3: begin
                            scl_oe <= 1'b1;
                            shifter <= {wr_byte, 1'b0}; // wr_byte in [8:1], drive [8]
                            bit_idx <= 4'd0;
                            state   <= S_DATA; phase<=0;
                        end
                        default: ;
                    endcase
                end
                S_DATA: if (qtick) begin
                    phase <= phase + 1'b1;
                    case (phase)
                        2'd0: sda_oe <= ~shifter[8] ? 1'b1:1'b0;
                        2'd1: scl_oe <= 1'b0;
                        2'd3: begin
                            scl_oe  <= 1'b1;
                            shifter <= {shifter[7:0], 1'b0};
                            if (bit_idx == 4'd7) begin state<=S_DACK; phase<=0; end
                            else bit_idx <= bit_idx + 1'b1;
                        end
                        default: ;
                    endcase
                end
                S_DACK: if (qtick) begin
                    phase <= phase + 1'b1;
                    case (phase)
                        2'd0: sda_oe <= 1'b0;
                        2'd1: scl_oe <= 1'b0;
                        2'd2: ack    <= ~sda_in;
                        2'd3: begin scl_oe <= 1'b1; state<=S_STOP; phase<=0; end
                        default: ;
                    endcase
                end
                S_STOP: if (qtick) begin
                    phase <= phase + 1'b1;
                    case (phase)
                        2'd0: sda_oe <= 1'b1;  // SDA low
                        2'd1: scl_oe <= 1'b0;  // SCL high
                        2'd2: sda_oe <= 1'b0;  // SDA low->high while SCL high = STOP
                        2'd3: state  <= S_DONE;
                        default: ;
                    endcase
                end
                S_DONE: begin
                    busy <= 1'b0; done <= 1'b1; state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

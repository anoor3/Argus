// ============================================================================
// trace_buffer.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Circular event buffer backed by a simple dual-port RAM (maps to BRAM on an
//   FPGA). It stores fixed-width event records written by the event_logger and
//   lets the host pop them out in order. When more events arrive than capacity,
//   the oldest are overwritten and an overflow flag is raised so measurement
//   loss is visible rather than silent.
//
// Interface:
//   clk, rst           : clock / sync reset
//   wr_en, wr_data     : write one record (from event_logger)
//   rd_en              : pop one record toward the host
//   rd_data            : record at the read pointer (valid after rd_en)
//   rd_valid           : strobe marking rd_data valid
//   count[AW:0]        : number of stored (unread) records
//   overflow           : sticky flag: at least one record was overwritten
//   full, empty        : status
//
// Behavior:
//   - Write advances the write pointer; if the buffer is full the write still
//     happens (circular overwrite) and the read pointer is pushed forward, and
//     overflow latches high. This keeps the most recent history, which is what
//     you want when a trigger fires.
//   - Read pops from the read pointer when not empty.
//   - overflow is sticky until reset (so the host always learns loss occurred).
//
// Design tradeoff:
//   Overwrite-oldest (vs. stop-on-full) keeps the newest events around a
//   trigger, at the cost of losing the oldest. The overflow flag makes that
//   tradeoff auditable instead of hidden — biasing results silently is the
//   thing the project rules forbid.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module trace_buffer #(
    parameter int DW = 96,
    parameter int AW = 8            // depth = 2**AW records
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          wr_en,
    input  wire [DW-1:0] wr_data,
    input  wire          rd_en,
    output reg  [DW-1:0] rd_data,
    output reg           rd_valid,
    output wire [AW:0]   count,
    output reg           overflow,
    output wire          full,
    output wire          empty
);

    localparam int DEPTH = (1 << AW);

    reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW:0]   wptr, rptr;   // extra MSB to distinguish full vs empty

    wire [AW-1:0] waddr = wptr[AW-1:0];
    wire [AW-1:0] raddr = rptr[AW-1:0];

    assign count = wptr - rptr;
    assign full  = (count == DEPTH[AW:0]);
    assign empty = (wptr == rptr);

    always @(posedge clk) begin
        if (rst) begin
            wptr <= 0; rptr <= 0; overflow <= 1'b0;
            rd_data <= '0; rd_valid <= 1'b0;
        end else begin
            rd_valid <= 1'b0;

            // Write path (circular overwrite on full)
            if (wr_en) begin
                mem[waddr] <= wr_data;
                wptr <= wptr + 1'b1;
                if (full && !(rd_en && !empty)) begin
                    // overwrite oldest: advance read pointer, mark overflow
                    rptr     <= rptr + 1'b1;
                    overflow <= 1'b1;
                end
            end

            // Read path
            if (rd_en && !empty) begin
                rd_data  <= mem[raddr];
                rd_valid <= 1'b1;
                rptr     <= rptr + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire

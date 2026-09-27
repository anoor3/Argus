// ============================================================================
// event_logger.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Central point that turns monitor events into timestamped trace records.
//   It collects one-cycle event pulses from several sources, stamps each with
//   the current 64-bit timebase value, packs a fixed-width record, and issues a
//   write to the trace buffer. It also arbitrates when multiple sources fire on
//   the same cycle so no event is silently lost.
//
// Record: { timestamp[63:0], source_id[7:0], code[7:0], value[15:0] } = 96 bits
//
// Interface:
//   clk, rst              : clock / sync reset
//   en                    : master capture enable (freeze when low)
//   time_now[63:0]        : shared timebase value
//   src{0,1,2}_valid      : per-source event strobe
//   src{0,1,2}_id[7:0]    : source id
//   src{0,1,2}_code[7:0]  : event code
//   src{0,1,2}_value[15:0]: event value
//   rec_wr, rec_data      : write strobe + packed record to trace_buffer
//   event_count[31:0]     : total events logged (for CSR readout)
//   drop_count[31:0]      : events dropped due to simultaneous collision that
//                           could not be serialized (should stay 0 in normal
//                           operation; exposed so loss is auditable)
//
// Simultaneous events:
//   Up to one record is written per cycle. If two sources fire together, the
//   lower-index source is written this cycle and the other is held one cycle in
//   a 1-deep skid; a third simultaneous collision while the skid is occupied
//   increments drop_count (made visible, never hidden).
//
// Design tradeoff:
//   A 1-deep skid (vs. a full per-source FIFO) covers realistic monitor rates
//   cheaply; the drop_count makes the limit measurable for the characterization
//   phase instead of pretending it cannot happen.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"

module event_logger (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire [63:0] time_now,

    input  wire        src0_valid, input wire [7:0] src0_id,
    input  wire [7:0]  src0_code,  input wire [15:0] src0_value,
    input  wire        src1_valid, input wire [7:0] src1_id,
    input  wire [7:0]  src1_code,  input wire [15:0] src1_value,
    input  wire        src2_valid, input wire [7:0] src2_id,
    input  wire [7:0]  src2_code,  input wire [15:0] src2_value,

    output reg          rec_wr,
    output reg  [95:0]  rec_data,
    output reg  [31:0]  event_count,
    output reg  [31:0]  drop_count
);

    // 1-deep skid for a colliding event
    reg        skid_occ;
    reg [63:0] skid_ts;
    reg [7:0]  skid_id, skid_code;
    reg [15:0] skid_val;

    function [95:0] pack(input [63:0] ts, input [7:0] id,
                         input [7:0] code, input [15:0] val);
        pack = {ts, id, code, val};
    endfunction

    // Count how many sources fired this cycle
    wire [1:0] nfire = src0_valid + src1_valid + src2_valid;

    always @(posedge clk) begin
        if (rst) begin
            rec_wr <= 1'b0; rec_data <= 96'd0;
            event_count <= 32'd0; drop_count <= 32'd0;
            skid_occ <= 1'b0; skid_ts<=0; skid_id<=0; skid_code<=0; skid_val<=0;
        end else begin
            rec_wr <= 1'b0;

            if (en) begin
                // Priority: drain skid first, then src0, src1, src2.
                if (skid_occ) begin
                    rec_data    <= pack(skid_ts, skid_id, skid_code, skid_val);
                    rec_wr      <= 1'b1;
                    event_count <= event_count + 1'b1;
                    skid_occ    <= 1'b0;
                    // Any source firing this cycle must be buffered/counted.
                    if (nfire >= 2) drop_count <= drop_count + (nfire - 1);
                    // stash the highest-priority current one into skid
                    if (src0_valid) begin
                        skid_occ<=1; skid_ts<=time_now; skid_id<=src0_id; skid_code<=src0_code; skid_val<=src0_value;
                    end else if (src1_valid) begin
                        skid_occ<=1; skid_ts<=time_now; skid_id<=src1_id; skid_code<=src1_code; skid_val<=src1_value;
                    end else if (src2_valid) begin
                        skid_occ<=1; skid_ts<=time_now; skid_id<=src2_id; skid_code<=src2_code; skid_val<=src2_value;
                    end
                end else if (src0_valid) begin
                    rec_data    <= pack(time_now, src0_id, src0_code, src0_value);
                    rec_wr      <= 1'b1;
                    event_count <= event_count + 1'b1;
                    if (src1_valid && src2_valid) drop_count <= drop_count + 1'b1;
                    if (src1_valid) begin
                        skid_occ<=1; skid_ts<=time_now; skid_id<=src1_id; skid_code<=src1_code; skid_val<=src1_value;
                    end else if (src2_valid) begin
                        skid_occ<=1; skid_ts<=time_now; skid_id<=src2_id; skid_code<=src2_code; skid_val<=src2_value;
                    end
                end else if (src1_valid) begin
                    rec_data    <= pack(time_now, src1_id, src1_code, src1_value);
                    rec_wr      <= 1'b1;
                    event_count <= event_count + 1'b1;
                    if (src2_valid) begin
                        skid_occ<=1; skid_ts<=time_now; skid_id<=src2_id; skid_code<=src2_code; skid_val<=src2_value;
                    end
                end else if (src2_valid) begin
                    rec_data    <= pack(time_now, src2_id, src2_code, src2_value);
                    rec_wr      <= 1'b1;
                    event_count <= event_count + 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire

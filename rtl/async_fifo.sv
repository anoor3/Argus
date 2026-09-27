// ============================================================================
// async_fifo.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Dual-clock FIFO for moving multi-bit data safely between a write clock and
//   a read clock. Used when a DUT interface runs on its own clock and its data
//   must reach the ARGUS core domain without metastability corrupting a word.
//
// How safety is achieved:
//   The only things that cross domains are the read/write pointers, and they
//   cross as GRAY code (one bit changes per increment) through a flop
//   synchronizer. A Gray pointer that is caught mid-transition resolves to
//   either the old or new value, never a bogus intermediate, so full/empty
//   comparisons are always safe.
//
// Interface:
//   wclk,wrst / rclk,rrst : write and read domain clock+reset
//   wr_en, wdata / full   : write side
//   rd_en, rdata / empty  : read side
//
// Full/empty generation:
//   - empty : read Gray pointer == synchronized write Gray pointer.
//   - full  : write Gray pointer == synchronized read Gray pointer with the
//             two MSBs inverted (the classic wrapped-around condition).
//
// Edge/error cases:
//   - write while full: ignored (no overwrite).
//   - read while empty: rdata holds; no underflow.
//
// Design tradeoff:
//   Gray-pointer CDC (vs. handshake per word) gives high throughput across
//   domains at the cost of a power-of-two depth requirement.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module async_fifo #(
    parameter int DW    = 8,
    parameter int AW    = 4          // depth = 2**AW
) (
    input  wire          wclk, input wire wrst,
    input  wire          wr_en,
    input  wire [DW-1:0] wdata,
    output wire          full,

    input  wire          rclk, input wire rrst,
    input  wire          rd_en,
    output reg  [DW-1:0] rdata,
    output wire          empty
);

    localparam int DEPTH = (1 << AW);

    reg [DW-1:0] mem [0:DEPTH-1];

    // Binary and Gray pointers (one extra MSB for full/empty distinction).
    reg  [AW:0] wbin, wgray;
    reg  [AW:0] rbin, rgray;

    // Synchronized opposite-domain Gray pointers.
    reg  [AW:0] wgray_rsync1, wgray_rsync2; // write ptr seen in read domain
    reg  [AW:0] rgray_wsync1, rgray_wsync2; // read ptr seen in write domain

    function [AW:0] bin2gray(input [AW:0] b); bin2gray = b ^ (b >> 1); endfunction

    // ---- write domain ----
    wire [AW:0] wbin_next  = wbin + (wr_en & ~full);
    always @(posedge wclk) begin
        if (wrst) begin wbin <= 0; wgray <= 0; end
        else begin
            if (wr_en && !full) mem[wbin[AW-1:0]] <= wdata;
            wbin  <= wbin_next;
            wgray <= bin2gray(wbin_next);
        end
    end

    always @(posedge wclk) begin
        if (wrst) begin rgray_wsync1 <= 0; rgray_wsync2 <= 0; end
        else begin rgray_wsync1 <= rgray; rgray_wsync2 <= rgray_wsync1; end
    end
    // full: registered write gray == read gray with top two bits flipped.
    // Uses the registered wgray (not the combinational next) to avoid a
    // combinational loop full -> wbin_next -> wgray -> full.
    assign full = (wgray == {~rgray_wsync2[AW:AW-1], rgray_wsync2[AW-2:0]});

    // ---- read domain ----
    wire [AW:0] rbin_next  = rbin + (rd_en & ~empty);
    always @(posedge rclk) begin
        if (rrst) begin rbin <= 0; rgray <= 0; rdata <= 0; end
        else begin
            if (rd_en && !empty) rdata <= mem[rbin[AW-1:0]];
            rbin  <= rbin_next;
            rgray <= bin2gray(rbin_next);
        end
    end

    always @(posedge rclk) begin
        if (rrst) begin wgray_rsync1 <= 0; wgray_rsync2 <= 0; end
        else begin wgray_rsync1 <= wgray; wgray_rsync2 <= wgray_rsync1; end
    end
    // empty: read gray == synchronized write gray
    assign empty = (rgray == wgray_rsync2);

endmodule

`default_nettype wire

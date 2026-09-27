// ============================================================================
// cdc_sync.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Clock-domain-crossing primitives. Asynchronous DUT signals must not be
//   sampled directly by ARGUS logic or metastability could be latched as real
//   data. This file provides the two safe building blocks used everywhere:
//     - cdc_sync_bit   : N-stage flop synchronizer for a single-bit level
//     - cdc_pulse_sync : safely moves a one-cycle pulse across domains via a
//                        toggle + synchronizer + edge-detect
//
// Why multi-bit direct sync is unsafe:
//   Independent bits of a bus can resolve on different cycles, producing a
//   value that never existed. Only single-bit levels (or gray-coded pointers,
//   see async_fifo) may cross with a flop synchronizer.
//
// Failure mode guarded against:
//   Metastability: a flop sampled near its setup/hold window can hover between
//   0 and 1. Extra flop stages give it time to resolve before use.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

// ---- N-stage single-bit level synchronizer ----
module cdc_sync_bit #(
    parameter int STAGES = 2
) (
    input  wire dclk,     // destination clock
    input  wire drst,     // destination reset (sync, active-high)
    input  wire async_in, // signal from another domain
    output wire sync_out
);
    reg [STAGES-1:0] sync_ff;
    always @(posedge dclk) begin
        if (drst) sync_ff <= '0;
        else      sync_ff <= {sync_ff[STAGES-2:0], async_in};
    end
    assign sync_out = sync_ff[STAGES-1];
endmodule

// ---- one-cycle pulse crossing (source pulse -> destination pulse) ----
module cdc_pulse_sync #(
    parameter int STAGES = 2
) (
    input  wire sclk, input wire srst, input wire src_pulse,
    input  wire dclk, input wire drst, output wire dst_pulse
);
    // Source: toggle a level on each input pulse.
    reg toggle;
    always @(posedge sclk) begin
        if (srst) toggle <= 1'b0;
        else if (src_pulse) toggle <= ~toggle;
    end

    // Destination: synchronize the toggle, then detect an edge.
    wire tog_sync;
    cdc_sync_bit #(.STAGES(STAGES)) u_s (
        .dclk(dclk), .drst(drst), .async_in(toggle), .sync_out(tog_sync)
    );
    reg tog_sync_d;
    always @(posedge dclk) begin
        if (drst) tog_sync_d <= 1'b0;
        else      tog_sync_d <= tog_sync;
    end
    assign dst_pulse = tog_sync ^ tog_sync_d;
endmodule

`default_nettype wire

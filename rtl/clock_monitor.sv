// ============================================================================
// clock_monitor.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Detects whether an external DUT clock is running. It counts edges of the
//   monitored clock (brought into the ARGUS domain) over a fixed measurement
//   window and flags "clock lost" when too few edges are seen, and "clock ok"
//   when activity returns. This catches a stuck/absent clock during bring-up.
//
// Interface:
//   clk, rst            : ARGUS clock / sync reset
//   dut_clk_in          : the external clock being monitored (async)
//   window_cyc[15:0]    : measurement window length in ARGUS clocks
//   min_edges[15:0]     : minimum edges within a window to consider "alive"
//   ev_valid            : 1-cycle pulse when the alive/lost state changes
//   ev_code[7:0]        : EVC_CLK_OK or EVC_CLK_LOST
//   ev_value[15:0]      : edge count observed in the window that triggered
//
// Method:
//   dut_clk_in is 2-flop synchronized; rising edges of the synced version are
//   counted. At each window boundary the count is compared to min_edges to
//   decide alive/lost, and a transition emits an event. This is a *ratio*
//   measurement, not an absolute frequency, which is enough to detect a dead
//   or grossly wrong clock without a second reference oscillator.
//
// Edge/error cases:
//   - Clock exactly at threshold: >= min_edges counts as alive (defined).
//   - Reset: starts in "unknown" and emits the first real state at window end.
//
// Design tradeoff:
//   Synchronizer-based edge counting works for DUT clocks well below the ARGUS
//   clock. Measuring a clock near/above the ARGUS clock needs a different
//   method (documented limitation, not silently wrong).
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"

module clock_monitor (
    input  wire        clk,
    input  wire        rst,
    input  wire        dut_clk_in,
    input  wire [15:0] window_cyc,
    input  wire [15:0] min_edges,
    output reg         ev_valid,
    output reg  [7:0]  ev_code,
    output reg  [15:0] ev_value
);

    reg s1, s2, s2_d;
    always @(posedge clk) begin
        if (rst) begin s1<=0; s2<=0; s2_d<=0; end
        else     begin s1<=dut_clk_in; s2<=s1; s2_d<=s2; end
    end
    wire edge_seen = s2 & ~s2_d;

    reg [15:0] win_cnt;
    reg [15:0] edge_cnt;
    reg        alive;     // current decision
    reg        have_state;

    always @(posedge clk) begin
        if (rst) begin
            win_cnt <= 16'd0; edge_cnt <= 16'd0;
            alive <= 1'b0; have_state <= 1'b0;
            ev_valid <= 1'b0; ev_code <= 8'd0; ev_value <= 16'd0;
        end else begin
            ev_valid <= 1'b0;
            if (edge_seen) edge_cnt <= edge_cnt + 1'b1;

            if (win_cnt == window_cyc - 1) begin
                // window boundary: decide
                if ((edge_cnt + (edge_seen ? 16'd1 : 16'd0)) >= min_edges) begin
                    if (!alive || !have_state) begin
                        ev_valid <= 1'b1; ev_code <= `EVC_CLK_OK;
                        ev_value <= edge_cnt + (edge_seen ? 16'd1 : 16'd0);
                    end
                    alive <= 1'b1;
                end else begin
                    if (alive || !have_state) begin
                        ev_valid <= 1'b1; ev_code <= `EVC_CLK_LOST;
                        ev_value <= edge_cnt + (edge_seen ? 16'd1 : 16'd0);
                    end
                    alive <= 1'b0;
                end
                have_state <= 1'b1;
                win_cnt    <= 16'd0;
                edge_cnt   <= 16'd0;
            end else begin
                win_cnt <= win_cnt + 1'b1;
            end
        end
    end

endmodule

`default_nettype wire

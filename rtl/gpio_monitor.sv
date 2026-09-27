// ============================================================================
// gpio_monitor.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Watches a single asynchronous DUT GPIO line and emits an event on each
//   qualified edge, with optional debounce. Edges are timestamped downstream by
//   the event_logger so multiple GPIO/reset/clock events share one timeline.
//
// Interface:
//   clk, rst          : ARGUS core clock / sync reset
//   gpio_in           : asynchronous DUT signal (crosses domains internally)
//   debounce_cyc[7:0] : line must be stable this many cycles before an edge
//                       counts (0 = no debounce)
//   ev_valid          : 1-cycle pulse when an edge event is produced
//   ev_code[7:0]      : EVC_RISE or EVC_FALL
//   ev_value[15:0]    : new stable level in bit 0
//
// State/cycle behavior:
//   - gpio_in is passed through a 2-flop synchronizer (async -> clk).
//   - A debounce counter requires the synchronized level to hold N cycles
//     before the level is accepted; a glitch shorter than N is ignored.
//   - On an accepted level change, ev_valid pulses with rise/fall code.
//
// Edge/error cases:
//   - Glitch shorter than debounce window: no event (verified).
//   - Back-to-back edges after debounce: one event each.
//
// Design tradeoff:
//   Per-line debounce in the monitor (vs. raw capture) trades a few cycles of
//   latency for immunity to mechanical/again noise, which is what makes edge
//   counts trustworthy.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"

module gpio_monitor (
    input  wire        clk,
    input  wire        rst,
    input  wire        gpio_in,
    input  wire [7:0]  debounce_cyc,
    output reg         ev_valid,
    output reg  [7:0]  ev_code,
    output reg  [15:0] ev_value
);

    // 2-flop synchronizer
    reg s1, s2;
    always @(posedge clk) begin
        if (rst) begin s1 <= 1'b0; s2 <= 1'b0; end
        else     begin s1 <= gpio_in; s2 <= s1; end
    end

    reg        stable_lvl;   // last accepted (debounced) level
    reg [7:0]  cnt;          // cycles the candidate has been held
    reg        cand;         // candidate level being timed

    always @(posedge clk) begin
        if (rst) begin
            stable_lvl <= 1'b0;
            cand       <= 1'b0;
            cnt        <= 8'd0;
            ev_valid   <= 1'b0;
            ev_code    <= 8'd0;
            ev_value   <= 16'd0;
        end else begin
            ev_valid <= 1'b0;
            if (s2 != cand) begin
                cand <= s2;      // new candidate, restart debounce
                cnt  <= 8'd0;
            end else if (s2 != stable_lvl) begin
                if (cnt >= debounce_cyc) begin
                    stable_lvl <= s2;
                    ev_valid   <= 1'b1;
                    ev_code    <= s2 ? `EVC_RISE : `EVC_FALL;
                    ev_value   <= {15'd0, s2};
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end

endmodule

`default_nettype wire

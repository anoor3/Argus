// ============================================================================
// trigger_engine.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Watches the logged event stream and, when a programmed condition matches,
//   asserts a trigger. It supports a post-trigger delay (capture N more events
//   after the match, then freeze) so the trace holds context around the event
//   of interest. When frozen, it drops capture-enable so the trace buffer stops
//   changing and the host can read a stable snapshot.
//
// Interface:
//   clk, rst              : clock / sync reset
//   arm                   : 1-cycle pulse to arm the trigger (re-arm)
//   match_src[7:0]        : source id to match (0xFF = any)
//   match_code[7:0]       : event code to match (0xFF = any)
//   post_count[15:0]      : events to keep logging after the match
//   ev_valid              : an event was logged this cycle
//   ev_src[7:0], ev_code  : the logged event's source/code
//   capture_en            : high while capture should proceed (feeds logger en)
//   triggered             : sticky flag: the condition matched since arm
//   trig_pulse            : 1-cycle pulse at the moment of match
//
// State machine: IDLE(disarmed) -> ARMED -> POST(counting) -> FROZEN.
//
// Edge/error cases:
//   - post_count == 0: freeze immediately on match.
//   - match_src/code == 0xFF acts as wildcard.
//   - arm during FROZEN re-arms and resumes capture.
//
// Design tradeoff:
//   Freezing capture (vs. a separate mark bit) gives a guaranteed-stable buffer
//   for readout without racing new writes, at the cost of stopping acquisition.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module trigger_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        arm,
    input  wire [7:0]  match_src,
    input  wire [7:0]  match_code,
    input  wire [15:0] post_count,
    input  wire        ev_valid,
    input  wire [7:0]  ev_src,
    input  wire [7:0]  ev_code,
    output reg         capture_en,
    output reg         triggered,
    output reg         trig_pulse
);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_ARMED = 2'd1,
                     S_POST  = 2'd2,
                     S_FROZEN= 2'd3;

    reg [1:0]  state;
    reg [15:0] post_left;

    wire src_hit  = (match_src  == 8'hFF) || (ev_src  == match_src);
    wire code_hit = (match_code == 8'hFF) || (ev_code == match_code);
    wire hit      = ev_valid && src_hit && code_hit;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE; capture_en <= 1'b1;
            triggered <= 1'b0; trig_pulse <= 1'b0; post_left <= 16'd0;
        end else begin
            trig_pulse <= 1'b0;

            // arm takes priority: (re)start acquisition
            if (arm) begin
                state      <= S_ARMED;
                capture_en <= 1'b1;
                triggered  <= 1'b0;
            end else begin
                case (state)
                    S_IDLE: capture_en <= 1'b1;  // free-run until armed
                    S_ARMED: begin
                        capture_en <= 1'b1;
                        if (hit) begin
                            triggered  <= 1'b1;
                            trig_pulse <= 1'b1;
                            if (post_count == 16'd0) begin
                                capture_en <= 1'b0;
                                state      <= S_FROZEN;
                            end else begin
                                post_left <= post_count;
                                state     <= S_POST;
                            end
                        end
                    end
                    S_POST: begin
                        capture_en <= 1'b1;
                        if (ev_valid) begin
                            if (post_left <= 16'd1) begin
                                capture_en <= 1'b0;
                                state      <= S_FROZEN;
                            end else begin
                                post_left <= post_left - 1'b1;
                            end
                        end
                    end
                    S_FROZEN: capture_en <= 1'b0;
                    default:  state <= S_IDLE;
                endcase
            end
        end
    end

endmodule

`default_nettype wire

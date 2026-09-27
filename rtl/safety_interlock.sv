// ============================================================================
// safety_interlock.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Hardware guard that enforces the fault-injection rules in docs/SAFETY.md.
//   No fault may be applied unless the system is explicitly ARMED and globally
//   ENABLED, the requested duration is within a hard limit, and the request is
//   not contradictory. On any violation, reset, or duration expiry, it forces
//   all fault outputs to a benign (inactive) state.
//
// Two-step arming: `arm` latches an armed state; a separate `fire` actually
//   requests injection. A single stray write can never inject.
//
// Interface:
//   clk, rst              : clock / sync reset
//   global_en             : master enable (must be high to allow any fault)
//   arm                   : 1-cycle pulse to arm
//   disarm                : 1-cycle pulse to clear armed state
//   fire                  : request to begin injection (needs armed & global_en)
//   duration[15:0]        : requested injection length in cycles
//   max_duration[15:0]    : hard cap; requests above this are rejected
//   fault_active          : high while an approved injection is in progress
//   time_left[15:0]       : remaining cycles of the active injection
//   armed                 : current armed state (status)
//   violation             : 1-cycle pulse when a request was rejected
//
// State: DISARMED -> ARMED -> ACTIVE (counts down) -> back to ARMED.
//
// Edge/error cases:
//   - fire while not armed or !global_en: rejected, violation pulses.
//   - duration==0 or > max_duration: rejected.
//   - global_en drops mid-injection: fault_active forced low immediately.
//
// Design tradeoff:
//   Enforcing safety in RTL (vs. trusting host software) means a software bug
//   cannot drive the DUT into an unsafe state; the cost is a small FSM in the
//   fault path.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module safety_interlock (
    input  wire        clk,
    input  wire        rst,
    input  wire        global_en,
    input  wire        arm,
    input  wire        disarm,
    input  wire        fire,
    input  wire [15:0] duration,
    input  wire [15:0] max_duration,
    output reg         fault_active,
    output reg  [15:0] time_left,
    output reg         armed,
    output reg         violation
);

    localparam [1:0] S_DISARM=0, S_ARMED=1, S_ACTIVE=2;
    reg [1:0] state;

    always @(posedge clk) begin
        if (rst) begin
            state<=S_DISARM; armed<=1'b0; fault_active<=1'b0;
            time_left<=16'd0; violation<=1'b0;
        end else begin
            violation <= 1'b0;

            // Global disable always forces benign state.
            if (!global_en) begin
                fault_active <= 1'b0;
                time_left    <= 16'd0;
                if (state == S_ACTIVE) state <= S_ARMED;
            end

            case (state)
                S_DISARM: begin
                    armed <= 1'b0; fault_active <= 1'b0;
                    if (arm && global_en) begin armed<=1'b1; state<=S_ARMED; end
                    if (fire) violation <= 1'b1; // cannot fire while disarmed
                end
                S_ARMED: begin
                    armed <= 1'b1; fault_active <= 1'b0;
                    if (disarm) begin armed<=1'b0; state<=S_DISARM; end
                    else if (fire) begin
                        // Validate the request.
                        if (!global_en || duration==16'd0 || duration>max_duration) begin
                            violation <= 1'b1;   // rejected, stay armed
                        end else begin
                            fault_active <= 1'b1;
                            time_left    <= duration;
                            state        <= S_ACTIVE;
                        end
                    end
                end
                S_ACTIVE: begin
                    if (!global_en) begin
                        fault_active <= 1'b0; state <= S_ARMED;
                    end else if (time_left <= 16'd1) begin
                        fault_active <= 1'b0;   // auto-restore at expiry
                        time_left    <= 16'd0;
                        state        <= S_ARMED;
                    end else begin
                        time_left <= time_left - 1'b1;
                    end
                    // A second fire during active injection is contradictory.
                    if (fire) violation <= 1'b1;
                end
                default: state <= S_DISARM;
            endcase
        end
    end

endmodule

`default_nettype wire

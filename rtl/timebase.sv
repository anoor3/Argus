// ============================================================================
// timebase.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Free-running cycle counter that provides a single monotonic time basis so
//   that independent event sources (monitors, protocol masters, faults) can be
//   correlated on one timeline. Every timestamp in ARGUS comes from here.
//
// Interface:
//   clk        : system clock
//   rst        : synchronous, active-high reset -> counter returns to 0
//   en         : count enable; when low the counter holds (freeze support)
//   time_now   : current 64-bit timestamp (combinational view of the counter)
//   tick       : 1-cycle pulse each time the counter increments (en & !rst)
//
// State / cycle behavior:
//   - On reset, count <= 0.
//   - When en=1 and not in reset, count increments by 1 each rising edge.
//   - When en=0, count holds its value (used to freeze time during trace read).
//   - 64-bit width: at 50 MHz it will not roll over for ~11700 years, so
//     rollover is a tested corner (via a narrow-width param instance) rather
//     than an expected operating condition.
//
// Edge/error cases:
//   - Reset while counting: count must go to 0 on the next clock, deterministic.
//   - Rollover: parameterized WIDTH lets the TB drive a small counter to the
//     max value and confirm wrap to 0 without an off-by-one.
//
// Design tradeoff:
//   A single shared counter (vs. per-monitor counters) guarantees all events
//   share one clock and one origin, which is what makes cross-source
//   correlation valid. Cost is one wide adder in the primary clock domain.
// ============================================================================
`default_nettype none

module timebase #(
    parameter int WIDTH = 64
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              en,
    output wire [WIDTH-1:0]  time_now,
    output wire              tick
);

    reg [WIDTH-1:0] count;

    always @(posedge clk) begin
        if (rst)
            count <= '0;
        else if (en)
            count <= count + 1'b1;
    end

    assign time_now = count;
    assign tick     = en & ~rst;

endmodule

`default_nettype wire

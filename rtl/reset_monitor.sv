// ============================================================================
// reset_monitor.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Observes a DUT reset line and emits events on assertion and deassertion,
//   and measures how many cycles reset was held. Bring-up bugs often come from
//   resets that are too short or released in the wrong order; this makes the
//   timing observable and correlated on the shared timebase.
//
// Interface:
//   clk, rst           : ARGUS clock / sync reset (of the instrument itself)
//   dut_rst_in         : DUT reset line (assumed active-high), asynchronous
//   ev_valid           : 1-cycle pulse on an assert/deassert event
//   ev_code[7:0]       : EVC_RST_ASSERT or EVC_RST_DEASSRT
//   ev_value[15:0]     : on deassert, the measured assert width in cycles
//                        (saturating); 0 on assert
//
// State/cycle behavior:
//   - dut_rst_in is 2-flop synchronized.
//   - On 0->1 transition: emit ASSERT, start a width counter.
//   - While held: width counter increments (saturates at 16'hFFFF).
//   - On 1->0 transition: emit DEASSERT with the measured width.
//
// Edge/error cases:
//   - Width saturation for very long resets (defined, not wrap).
//   - Instrument reset clears state to a benign idle.
//
// Design tradeoff:
//   Measuring width in the monitor (vs. leaving it to software) gives a single
//   authoritative number tied to the same clock as every other event.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"

module reset_monitor (
    input  wire        clk,
    input  wire        rst,
    input  wire        dut_rst_in,
    output reg         ev_valid,
    output reg  [7:0]  ev_code,
    output reg  [15:0] ev_value
);

    reg s1, s2, s2_d;
    always @(posedge clk) begin
        if (rst) begin s1<=0; s2<=0; s2_d<=0; end
        else     begin s1<=dut_rst_in; s2<=s1; s2_d<=s2; end
    end

    reg [15:0] width;

    always @(posedge clk) begin
        if (rst) begin
            ev_valid <= 1'b0; ev_code <= 8'd0; ev_value <= 16'd0;
            width <= 16'd0;
        end else begin
            ev_valid <= 1'b0;
            // Count while asserted (held high)
            if (s2) begin
                if (width != 16'hFFFF) width <= width + 1'b1;
            end
            // Rising edge: assert
            if (s2 && !s2_d) begin
                ev_valid <= 1'b1;
                ev_code  <= `EVC_RST_ASSERT;
                ev_value <= 16'd0;
                width    <= 16'd0;
            end
            // Falling edge: deassert, report measured width
            if (!s2 && s2_d) begin
                ev_valid <= 1'b1;
                ev_code  <= `EVC_RST_DEASSRT;
                ev_value <= width;
            end
        end
    end

endmodule

`default_nettype wire

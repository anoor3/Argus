// ============================================================================
// fault_controller.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Applies the actual, bounded digital faults to DUT-facing signals, but ONLY
//   while the safety_interlock says fault_active is high. It never enforces its
//   own timing/arming — that is the interlock's job — so there is exactly one
//   place that decides whether a fault may be applied.
//
//   Supported fault types (docs/SAFETY.md):
//     FT_RESET_PULSE : drive dut_reset_out high
//     FT_BUS_SUPPRESS: mask a peripheral response (bus_suppress high)
//     FT_DATA_CORRUPT: XOR a data bus with corrupt_mask
//     FT_CLK_ENABLE  : gate a clock-enable (clk_en_out low) -- never the clock
//
// Interface:
//   clk, rst           : clock / sync reset
//   fault_active       : from safety_interlock (the only gate)
//   fault_type[2:0]    : which fault to apply while active
//   corrupt_mask[31:0] : XOR mask for data corruption
//   data_in[31:0]      : data bus to (optionally) corrupt
//   -- outputs to DUT / datapath --
//   data_out[31:0]     : data_in, or data_in ^ corrupt_mask when corrupting
//   dut_reset_out      : injected reset pulse
//   bus_suppress       : high to suppress a response
//   clk_en_out         : normally 1; forced 0 when gating clock-enable
//
// Behavior:
//   When fault_active is low, ALL outputs are benign: data passes through,
//   reset low, suppress low, clk_en high. When high, the selected effect is
//   applied. Because the interlock bounds fault_active, effects are inherently
//   bounded and auto-restore.
//
// Design tradeoff:
//   Pure combinational effect gated by a single fault_active (vs. its own
//   timers) keeps the safety argument simple: prove the interlock and the fault
//   is automatically bounded.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module fault_controller (
    input  wire        clk,
    input  wire        rst,
    input  wire        fault_active,
    input  wire [2:0]  fault_type,
    input  wire [31:0] corrupt_mask,
    input  wire [31:0] data_in,
    output reg  [31:0] data_out,
    output reg         dut_reset_out,
    output reg         bus_suppress,
    output reg         clk_en_out
);

    localparam [2:0] FT_NONE=0, FT_RESET_PULSE=1, FT_BUS_SUPPRESS=2,
                     FT_DATA_CORRUPT=3, FT_CLK_ENABLE=4;

    always @(posedge clk) begin
        if (rst) begin
            data_out<=32'd0; dut_reset_out<=1'b0;
            bus_suppress<=1'b0; clk_en_out<=1'b1;
        end else begin
            // Default benign every cycle.
            data_out      <= data_in;
            dut_reset_out <= 1'b0;
            bus_suppress  <= 1'b0;
            clk_en_out    <= 1'b1;

            if (fault_active) begin
                case (fault_type)
                    FT_RESET_PULSE:  dut_reset_out <= 1'b1;
                    FT_BUS_SUPPRESS: bus_suppress  <= 1'b1;
                    FT_DATA_CORRUPT: data_out      <= data_in ^ corrupt_mask;
                    FT_CLK_ENABLE:   clk_en_out    <= 1'b0;
                    default:         ; // FT_NONE: stay benign
                endcase
            end
        end
    end

endmodule

`default_nettype wire

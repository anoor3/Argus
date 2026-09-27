// ============================================================================
// cdc_sync_tb.sv -- self-checking testbench for cdc_sync.sv
//
// Checks:
//   1. cdc_sync_bit propagates a level after STAGES destination cycles.
//   2. cdc_pulse_sync turns one source pulse into exactly one dest pulse,
//      even though the two clocks differ in frequency.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module cdc_sync_tb;

    reg sclk = 0, srst = 1;
    reg dclk = 0, drst = 1;

    integer errors = 0;

    // Different clock rates to exercise the crossing.
    always #10 sclk = ~sclk;  // source 50 MHz
    always #17 dclk = ~dclk;  // dest ~29 MHz (asynchronous-ish)

    `WATCHDOG(500000)

    // ---- level sync ----
    reg  lvl_in = 0;
    wire lvl_out;
    cdc_sync_bit #(.STAGES(2)) u_lvl (
        .dclk(dclk), .drst(drst), .async_in(lvl_in), .sync_out(lvl_out)
    );

    // ---- pulse sync ----
    reg  src_pulse = 0;
    wire dst_pulse;
    integer dst_count = 0;
    cdc_pulse_sync #(.STAGES(2)) u_pls (
        .sclk(sclk), .srst(srst), .src_pulse(src_pulse),
        .dclk(dclk), .drst(drst), .dst_pulse(dst_pulse)
    );
    always @(posedge dclk) if (!drst && dst_pulse) dst_count = dst_count + 1;

    initial begin
        repeat (3) @(posedge dclk); drst = 0;
        repeat (3) @(posedge sclk); srst = 0;

        // Level crossing
        @(negedge sclk); lvl_in = 1;
        repeat (5) @(posedge dclk);
        `CHECK(lvl_out == 1'b1, "level propagates through synchronizer")
        @(negedge sclk); lvl_in = 0;
        repeat (5) @(posedge dclk);
        `CHECK(lvl_out == 1'b0, "level clears through synchronizer")

        // Single source pulse -> single dest pulse
        @(negedge sclk); src_pulse = 1;
        @(negedge sclk); src_pulse = 0;
        repeat (10) @(posedge dclk);
        `CHECK_EQ(dst_count, 1, "one source pulse yields one dest pulse")

        // Three more pulses spaced out -> total 4
        repeat (3) begin
            @(negedge sclk); src_pulse = 1;
            @(negedge sclk); src_pulse = 0;
            repeat (8) @(posedge dclk);
        end
        `CHECK_EQ(dst_count, 4, "four source pulses yield four dest pulses")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

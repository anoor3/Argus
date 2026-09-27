// ============================================================================
// safety_interlock_tb.sv -- self-checking testbench for safety_interlock.sv
//
// Checks (enforces docs/SAFETY.md rules):
//   1. fire while disarmed -> violation, no fault_active.
//   2. arm then fire (valid duration) -> fault_active for exactly `duration`
//      cycles, then auto-restores to inactive.
//   3. fire with duration > max_duration -> violation, no fault.
//   4. fire with duration == 0 -> violation, no fault.
//   5. global_en dropping mid-injection forces fault_active low immediately.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module safety_interlock_tb;

    reg        clk = 0, rst = 1;
    reg        global_en = 1, arm = 0, disarm = 0, fire = 0;
    reg  [15:0] duration = 16'd0, max_duration = 16'd20;
    wire       fault_active;
    wire [15:0] time_left;
    wire       armed, violation;

    integer errors = 0;
    integer viol_cnt = 0, active_cycles = 0;

    always #10 clk = ~clk;
    `WATCHDOG(600000)

    safety_interlock dut (
        .clk(clk), .rst(rst), .global_en(global_en),
        .arm(arm), .disarm(disarm), .fire(fire),
        .duration(duration), .max_duration(max_duration),
        .fault_active(fault_active), .time_left(time_left),
        .armed(armed), .violation(violation)
    );

    always @(posedge clk) if (!rst) begin
        if (violation)    viol_cnt = viol_cnt + 1;
        if (fault_active) active_cycles = active_cycles + 1;
    end

    task pulse_arm;   begin @(negedge clk); arm=1;   @(negedge clk); arm=0;   end endtask
    task pulse_fire;  begin @(negedge clk); fire=1;  @(negedge clk); fire=0;  end endtask

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;

        // 1. fire while disarmed -> violation, no fault
        viol_cnt = 0;
        duration = 16'd5;
        pulse_fire;
        repeat (2) @(posedge clk);
        `CHECK(viol_cnt >= 1, "fire while disarmed raises violation")
        `CHECK(fault_active == 1'b0, "no fault when disarmed")

        // 2. arm + valid fire -> fault for exactly `duration` cycles
        active_cycles = 0;
        pulse_arm;
        `CHECK(armed == 1'b1, "armed after arm")
        duration = 16'd5;
        pulse_fire;
        // wait for it to finish
        wait (fault_active == 1'b1);
        wait (fault_active == 1'b0);
        `CHECK_EQ(active_cycles, 5, "fault active for exactly duration cycles")

        // 3. duration > max -> violation, no fault
        viol_cnt = 0; active_cycles = 0;
        duration = 16'd50;   // > max_duration(20)
        pulse_fire;
        repeat (3) @(posedge clk);
        `CHECK(viol_cnt >= 1, "over-limit duration rejected")
        `CHECK_EQ(active_cycles, 0, "no fault on over-limit request")

        // 4. duration == 0 -> violation
        viol_cnt = 0;
        duration = 16'd0;
        pulse_fire;
        repeat (3) @(posedge clk);
        `CHECK(viol_cnt >= 1, "zero duration rejected")

        // 5. global_en drop mid-injection forces benign
        duration = 16'd15;
        pulse_fire;
        wait (fault_active == 1'b1);
        repeat (3) @(posedge clk);
        @(negedge clk); global_en = 0;
        @(posedge clk); #1;
        `CHECK(fault_active == 1'b0, "global_en drop forces fault off immediately")
        @(negedge clk); global_en = 1;

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

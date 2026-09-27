// ============================================================================
// safety_interlock_edge_tb.sv -- disarm and re-arm behavior around ACTIVE
//
// Covers:
//   1. A second fire during an ACTIVE injection is a contradiction -> violation.
//   2. After an injection completes, the interlock returns to ARMED so a new
//      valid fire can start another bounded injection (reusable).
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module safety_interlock_edge_tb;

    reg        clk = 0, rst = 1;
    reg        global_en = 1, arm = 0, disarm = 0, fire = 0;
    reg  [15:0] duration = 16'd0, max_duration = 16'd20;
    wire       fault_active;
    wire [15:0] time_left;
    wire       armed, violation;

    integer errors = 0;
    integer viol_cnt = 0, active_windows = 0;
    reg prev_active = 0;

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
        if (violation) viol_cnt = viol_cnt + 1;
        if (fault_active && !prev_active) active_windows = active_windows + 1;
        prev_active <= fault_active;
    end

    task pulse_arm;  begin @(negedge clk); arm=1;  @(negedge clk); arm=0;  end endtask
    task pulse_fire; begin @(negedge clk); fire=1; @(negedge clk); fire=0; end endtask

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;

        // Arm and start an injection
        pulse_arm;
        duration = 16'd10;
        pulse_fire;
        wait (fault_active == 1'b1);

        // Fire again mid-injection -> contradiction violation
        @(negedge clk); fire=1;
        @(negedge clk); fire=0;
        @(posedge clk); #1;
        `CHECK(viol_cnt >= 1, "second fire during ACTIVE raises violation")

        // Let it finish
        wait (fault_active == 1'b0);
        `CHECK(armed == 1'b1, "returns to ARMED after injection completes")

        // Reusable: a fresh valid fire starts a second window
        duration = 16'd6;
        pulse_fire;
        wait (fault_active == 1'b1);
        wait (fault_active == 1'b0);
        `CHECK_EQ(active_windows, 2, "two separate injection windows occurred")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

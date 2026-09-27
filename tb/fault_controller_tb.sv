// ============================================================================
// fault_controller_tb.sv -- integration test: fault_controller + safety_interlock
//
// Proves the safety-critical property: a fault effect appears ONLY while the
// interlock's fault_active is high (armed + valid fire), and auto-restores.
//
// Checks:
//   1. Before arming, no fault effect regardless of fault_type.
//   2. DATA_CORRUPT XORs data only during the active window, then restores.
//   3. RESET_PULSE asserts dut_reset_out only during the active window.
//   4. An unarmed fire produces no effect (interlock violation).
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module fault_controller_tb;

    reg        clk = 0, rst = 1;
    reg        global_en = 1, arm = 0, disarm = 0, fire = 0;
    reg  [15:0] duration = 16'd0, max_duration = 16'd50;

    wire       fault_active;
    wire [15:0] time_left; wire armed, violation;

    reg  [2:0]  fault_type = 3'd0;
    reg  [31:0] corrupt_mask = 32'h0;
    reg  [31:0] data_in = 32'hAAAA_5555;
    wire [31:0] data_out;
    wire       dut_reset_out, bus_suppress, clk_en_out;

    integer errors = 0;
    integer reset_cycles = 0;

    always #10 clk = ~clk;
    `WATCHDOG(800000)

    safety_interlock u_ilk (
        .clk(clk), .rst(rst), .global_en(global_en),
        .arm(arm), .disarm(disarm), .fire(fire),
        .duration(duration), .max_duration(max_duration),
        .fault_active(fault_active), .time_left(time_left),
        .armed(armed), .violation(violation)
    );

    fault_controller u_fc (
        .clk(clk), .rst(rst),
        .fault_active(fault_active), .fault_type(fault_type),
        .corrupt_mask(corrupt_mask), .data_in(data_in),
        .data_out(data_out), .dut_reset_out(dut_reset_out),
        .bus_suppress(bus_suppress), .clk_en_out(clk_en_out)
    );

    always @(posedge clk) if (!rst && dut_reset_out) reset_cycles = reset_cycles + 1;

    task pulse_arm;  begin @(negedge clk); arm=1;  @(negedge clk); arm=0;  end endtask
    task pulse_fire; begin @(negedge clk); fire=1; @(negedge clk); fire=0; end endtask

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (2) @(posedge clk);

        // 1. Before arming: no effect even with a fault_type set
        fault_type = 3'd3; corrupt_mask = 32'hFFFF_FFFF;
        repeat (3) @(posedge clk); #1;
        `CHECK_EQ(data_out, data_in, "no corruption before arming")
        `CHECK(dut_reset_out == 1'b0, "no reset before arming")

        // 2. DATA_CORRUPT during active window
        fault_type = 3'd3; corrupt_mask = 32'h0F0F_0F0F; duration = 16'd6;
        pulse_arm; pulse_fire;
        wait (fault_active == 1'b1); @(posedge clk); #1;
        `CHECK_EQ(data_out, data_in ^ 32'h0F0F_0F0F, "data corrupted while active")
        wait (fault_active == 1'b0); @(posedge clk); #1;
        `CHECK_EQ(data_out, data_in, "data restored after window")

        // 3. RESET_PULSE during active window
        reset_cycles = 0;
        fault_type = 3'd1; duration = 16'd4;
        pulse_fire;                    // still armed from before
        wait (fault_active == 1'b1);
        wait (fault_active == 1'b0);
        repeat (2) @(posedge clk);     // let the registered reset output drain
        `CHECK_EQ(reset_cycles, 4, "reset asserted for exactly duration cycles")

        // 4. Unarmed fire (disarm first) -> no effect
        @(negedge clk); disarm=1; @(negedge clk); disarm=0;
        reset_cycles = 0;
        fault_type = 3'd1; duration = 16'd4;
        pulse_fire;
        repeat (6) @(posedge clk);
        `CHECK_EQ(reset_cycles, 0, "no fault effect when unarmed")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

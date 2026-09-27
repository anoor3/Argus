// ============================================================================
// fault_controller_edge_tb.sv -- BUS_SUPPRESS and CLK_ENABLE fault types
//
// fault_controller_tb covers DATA_CORRUPT and RESET_PULSE. This covers the
// other two effect types, again gated by a real safety_interlock:
//   1. BUS_SUPPRESS raises bus_suppress only during the active window.
//   2. CLK_ENABLE drives clk_en_out low only during the active window.
//   3. Both restore to benign after the window.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module fault_controller_edge_tb;

    reg        clk = 0, rst = 1;
    reg        global_en = 1, arm = 0, disarm = 0, fire = 0;
    reg  [15:0] duration = 16'd0, max_duration = 16'd50;
    wire       fault_active; wire [15:0] time_left; wire armed, violation;

    reg  [2:0]  fault_type = 3'd0;
    reg  [31:0] data_in = 32'h1234_5678;
    wire [31:0] data_out;
    wire       dut_reset_out, bus_suppress, clk_en_out;

    integer errors = 0;
    integer suppress_cycles = 0, clkgate_cycles = 0;

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
        .corrupt_mask(32'd0), .data_in(data_in),
        .data_out(data_out), .dut_reset_out(dut_reset_out),
        .bus_suppress(bus_suppress), .clk_en_out(clk_en_out)
    );

    always @(posedge clk) if (!rst) begin
        if (bus_suppress)  suppress_cycles = suppress_cycles + 1;
        if (!clk_en_out)   clkgate_cycles  = clkgate_cycles + 1;
    end

    task pulse_arm;  begin @(negedge clk); arm=1;  @(negedge clk); arm=0;  end endtask
    task pulse_fire; begin @(negedge clk); fire=1; @(negedge clk); fire=0; end endtask

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        pulse_arm;

        // BUS_SUPPRESS
        fault_type = 3'd2; duration = 16'd5;
        pulse_fire;
        wait (fault_active == 1'b1); wait (fault_active == 1'b0);
        repeat (2) @(posedge clk);
        `CHECK_EQ(suppress_cycles, 5, "bus_suppress active exactly duration cycles")
        `CHECK(bus_suppress == 1'b0, "bus_suppress benign after window")

        // CLK_ENABLE gating
        fault_type = 3'd4; duration = 16'd7;
        pulse_fire;
        wait (fault_active == 1'b1); wait (fault_active == 1'b0);
        repeat (2) @(posedge clk);
        `CHECK_EQ(clkgate_cycles, 7, "clk_en gated low exactly duration cycles")
        `CHECK(clk_en_out == 1'b1, "clk_en restored high after window")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

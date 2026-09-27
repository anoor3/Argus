// ============================================================================
// argus_demo_tb.sv -- top-level demo: a sequencer program drives a safe fault
//
// Preloads a small program into argus_top's sequencer memory (via hierarchical
// reference), triggers RUN_SEQ over UART, and verifies that the programmed
// INJECT causes a bounded fault (dut_reset_out pulse) through the whole stack,
// then auto-restores. This is the end-to-end "safe fault injected and recovery
// observed" evidence called for in the build plan.
//
// Program: INJECT mask, DELAY, CLEAR, END.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_seq_ops.svh"
`include "argus_check.svh"

module argus_demo_tb;

    localparam int CPB = 8;

    reg  clk = 0, rst = 1;
    reg  rx_pin = 1;
    wire tx_pin;
    reg  gpio_in = 0, dut_rst_in = 0, dut_clk_in = 0;
    wire dut_reset_out, bus_suppress, clk_en_out, heartbeat;

    integer errors = 0;
    integer reset_pulses = 0;

    always #10 clk = ~clk;
    `WATCHDOG(4000000)

    argus_top #(.CLKS_PER_BIT(CPB), .TRACE_AW(6), .SEQ_AW(6)) dut (
        .clk(clk), .rst(rst),
        .uart_rx_pin(rx_pin), .uart_tx_pin(tx_pin),
        .gpio_in(gpio_in), .dut_rst_in(dut_rst_in), .dut_clk_in(dut_clk_in),
        .dut_reset_out(dut_reset_out), .bus_suppress(bus_suppress),
        .clk_en_out(clk_en_out), .heartbeat(heartbeat)
    );

    always @(posedge clk) if (!rst && dut_reset_out) reset_pulses = reset_pulses + 1;

    task send_byte(input [7:0] b);
        integer k;
        begin
            rx_pin=0; repeat(CPB) @(posedge clk);
            for (k=0;k<8;k=k+1) begin rx_pin=b[k]; repeat(CPB) @(posedge clk); end
            rx_pin=1; repeat(CPB) @(posedge clk);
        end
    endtask
    task send_frame(input [7:0] c, input [7:0] a, input [31:0] d);
        begin
            send_byte(c); send_byte(a);
            send_byte(d[31:24]); send_byte(d[23:16]);
            send_byte(d[15:8]); send_byte(d[7:0]);
        end
    endtask

    integer i;
    initial begin
        // Preload a program before releasing reset.
        dut.seq_mem[0] = {`OP_INJECT, 8'd0, 32'h0000_00F0};
        dut.seq_mem[1] = {`OP_DELAY,  8'd0, 32'd20};
        dut.seq_mem[2] = {`OP_CLEAR,  8'd0, 32'd0};
        dut.seq_mem[3] = {`OP_END,    8'd0, 32'd0};

        repeat (4) @(posedge clk); @(negedge clk); rst = 0;
        repeat (4) @(posedge clk);

        `CHECK(dut_reset_out === 1'b0, "no fault before RUN_SEQ")

        // RUN_SEQ command over UART
        send_frame(8'h04, 8'h00, 32'h0);

        // Give the sequencer + interlock time to run the injection window.
        repeat (400) @(posedge clk);

        `CHECK(reset_pulses > 0, "programmed INJECT produced a bounded reset pulse")
        `CHECK(dut_reset_out === 1'b0, "fault auto-restored to benign after window")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

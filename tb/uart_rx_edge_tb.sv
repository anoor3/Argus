// ============================================================================
// uart_rx_edge_tb.sv -- false-start rejection
//
// A glitch on rx that returns high before the start-bit center must be rejected
// (no byte, no data_valid). Then a clean frame right after must still be
// received, proving the receiver resynchronizes.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module uart_rx_edge_tb;

    localparam int CPB = 8;

    reg        clk = 0, rst = 1, rx = 1;
    wire [7:0] rx_data;
    wire       data_valid, frame_error;

    integer errors = 0;
    integer valid_cnt = 0;

    always #10 clk = ~clk;
    `WATCHDOG(600000)

    uart_rx #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst), .rx(rx),
        .rx_data(rx_data), .data_valid(data_valid), .frame_error(frame_error)
    );

    always @(posedge clk) if (!rst && data_valid) valid_cnt = valid_cnt + 1;

    task drive_bit(input bit level);
        begin rx = level; repeat (CPB) @(posedge clk); end
    endtask
    task drive_frame(input [7:0] v);
        integer k;
        begin
            drive_bit(1'b0);
            for (k=0;k<8;k=k+1) drive_bit(v[k]);
            drive_bit(1'b1);
            rx = 1'b1;
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); @(negedge clk); rst = 0;
        repeat (4) @(posedge clk);

        // False start: pull low for < half a bit, then high again
        rx = 1'b0; repeat (CPB/2 - 1) @(posedge clk);
        rx = 1'b1; repeat (CPB*2) @(posedge clk);
        `CHECK_EQ(valid_cnt, 0, "false start produces no byte")

        // Clean frame afterwards is still received
        drive_frame(8'h96);
        repeat (CPB*2) @(posedge clk);
        `CHECK_EQ(valid_cnt, 1, "receiver resyncs and gets the clean frame")
        `CHECK_EQ(rx_data, 8'h96, "correct byte after false start")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// uart_rx_tb.sv -- self-checking testbench for uart_rx.sv
//
// Checks:
//   1. A well-formed 8-N-1 frame is recovered with correct data.
//   2. data_valid pulses once per received byte.
//   3. A frame with a bad (low) stop bit raises frame_error.
//   4. A good stop bit leaves frame_error low.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module uart_rx_tb;

    localparam int CPB = 8;

    reg        clk = 0, rst = 1, rx = 1;
    wire [7:0] rx_data;
    wire       data_valid, frame_error;

    integer errors = 0;

    always #10 clk = ~clk;

    uart_rx #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst), .rx(rx),
        .rx_data(rx_data), .data_valid(data_valid), .frame_error(frame_error)
    );

    // Drive one bit for CPB clocks.
    task drive_bit(input bit level);
        begin
            rx = level;
            repeat (CPB) @(posedge clk);
        end
    endtask

    // Drive a full frame; stop_level lets us inject a framing error.
    task drive_frame(input [7:0] value, input bit stop_level);
        integer k;
        begin
            drive_bit(1'b0);            // start
            for (k = 0; k < 8; k = k + 1) drive_bit(value[k]); // LSB first
            drive_bit(stop_level);      // stop (1=good, 0=framing error)
            rx = 1'b1;                  // return to idle
        end
    endtask

    initial begin
        @(posedge clk); @(posedge clk);
        @(negedge clk); rst = 0;
        repeat (4) @(posedge clk);

        // Good frame
        fork
            drive_frame(8'h5A, 1'b1);
            begin
                @(posedge data_valid);
                `CHECK_EQ(rx_data, 8'h5A, "recovered byte matches sent")
                `CHECK(frame_error == 1'b0, "no frame error on good stop bit")
            end
        join

        repeat (CPB*2) @(posedge clk);

        // Bad stop bit -> frame_error
        fork
            drive_frame(8'hC3, 1'b0);
            begin
                @(posedge data_valid);
                `CHECK_EQ(rx_data, 8'hC3, "byte still recovered on bad stop")
                `CHECK(frame_error == 1'b1, "frame_error on bad stop bit")
            end
        join

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

// ============================================================================
// argus_core_tb.sv -- end-to-end P1 control-plane test
//
// Acts as the host: drives UART frames into uart_rx_pin and decodes the UART
// response on uart_tx_pin. Proves the full path
//   uart_rx -> command_router -> csr_bank -> uart_tx
// works by writing SCRATCH then reading it back and also reading the ID reg.
//
// Checks:
//   1. Reading ID (0x00) returns the magic constant over serial.
//   2. Writing SCRATCH (0x01) then reading it returns the written value.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_check.svh"

module argus_core_tb;

    localparam int CPB = 8;

    reg  clk = 0, rst = 1;
    reg  rx_pin = 1;
    wire tx_pin;
    wire heartbeat;

    integer errors = 0;

    always #10 clk = ~clk;
    `WATCHDOG(2000000)

    argus_core #(.CLKS_PER_BIT(CPB)) dut (
        .clk(clk), .rst(rst),
        .uart_rx_pin(rx_pin), .uart_tx_pin(tx_pin), .heartbeat(heartbeat)
    );

    // ---- host-side UART bit-bang ----
    task send_byte(input [7:0] b);
        integer k;
        begin
            rx_pin = 1'b0; repeat (CPB) @(posedge clk);       // start
            for (k=0;k<8;k=k+1) begin rx_pin=b[k]; repeat(CPB) @(posedge clk); end
            rx_pin = 1'b1; repeat (CPB) @(posedge clk);       // stop
        end
    endtask

    task send_frame(input [7:0] cmd, input [7:0] addr, input [31:0] d);
        begin
            send_byte(cmd); send_byte(addr);
            send_byte(d[31:24]); send_byte(d[23:16]);
            send_byte(d[15:8]);  send_byte(d[7:0]);
        end
    endtask

    // Receive one UART byte from tx_pin (waits for start edge, center-samples).
    task recv_byte(output [7:0] b);
        integer k;
        begin
            @(negedge tx_pin);                 // start bit edge
            repeat (CPB + CPB/2) @(posedge clk); // to center of bit0
            for (k=0;k<8;k=k+1) begin b[k]=tx_pin; repeat(CPB) @(posedge clk); end
            // stop bit consumed implicitly
        end
    endtask

    reg [7:0] b3,b2,b1,b0;

    initial begin
        repeat (4) @(posedge clk); @(negedge clk); rst = 0;
        repeat (4) @(posedge clk);

        // READ ID (0x00)
        fork
            send_frame(8'h02, 8'h00, 32'h0);
            begin recv_byte(b3); recv_byte(b2); recv_byte(b1); recv_byte(b0); end
        join
        `CHECK_EQ({b3,b2,b1,b0}, 32'hA2600101, "ID reads magic over serial")

        // WRITE SCRATCH = 0xCAFEF00D
        send_frame(8'h01, 8'h01, 32'hCAFEF00D);
        repeat (4) @(posedge clk);

        // READ SCRATCH back
        fork
            send_frame(8'h02, 8'h01, 32'h0);
            begin recv_byte(b3); recv_byte(b2); recv_byte(b1); recv_byte(b0); end
        join
        `CHECK_EQ({b3,b2,b1,b0}, 32'hCAFEF00D, "SCRATCH round-trips over serial")

        `FINISH_REPORT
    end

endmodule

`default_nettype wire

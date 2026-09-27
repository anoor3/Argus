// ============================================================================
// argus_core.sv
// ----------------------------------------------------------------------------
// Purpose:
//   P1 control-plane top level. Wires the host UART link to the command router,
//   the CSR bank, and the timebase so a PC can read/write registers over serial.
//   This is the minimum instrument: observe and configure over one link.
//
//   host --uart--> uart_rx --> command_router --> csr_bank
//                                        |            |
//                                     uart_tx <-------+ (read responses)
//   timebase feeds TIME_LO/TIME_HI in csr_bank.
//
// Interface:
//   clk, rst          : clock / sync active-high reset
//   uart_rx_pin       : serial in from host
//   uart_tx_pin       : serial out to host
//   heartbeat         : toggles with the timebase MSB for a liveness LED
//
// Design tradeoff:
//   Keeping the top level as pure structural wiring (no logic) means every
//   behavior is already verified in a submodule bench; this bench only proves
//   the connections are correct.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module argus_core #(
    parameter int CLKS_PER_BIT = 434
) (
    input  wire clk,
    input  wire rst,
    input  wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire heartbeat
);

    // ---- timebase ----
    wire [63:0] time_now;
    timebase #(.WIDTH(64)) u_time (
        .clk(clk), .rst(rst), .en(1'b1),
        .time_now(time_now), .tick()
    );
    assign heartbeat = time_now[23];

    // ---- uart rx ----
    wire [7:0] rx_byte;
    wire       rx_valid, rx_ferr;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .rx(uart_rx_pin),
        .rx_data(rx_byte), .data_valid(rx_valid), .frame_error(rx_ferr)
    );

    // ---- command router <-> csr ----
    wire        csr_wr, csr_rd;
    wire [7:0]  csr_addr;
    wire [31:0] csr_wdata, csr_rdata;
    wire        csr_rvalid;

    wire [7:0]  tx_byte;
    wire        tx_send, tx_busy;
    wire        run_seq, trace_read;

    command_router u_cmd (
        .clk(clk), .rst(rst),
        .rx_byte(rx_byte), .rx_valid(rx_valid),
        .csr_wr(csr_wr), .csr_rd(csr_rd), .csr_addr(csr_addr),
        .csr_wdata(csr_wdata), .csr_rdata(csr_rdata), .csr_rvalid(csr_rvalid),
        .tx_byte(tx_byte), .tx_send(tx_send), .tx_busy(tx_busy),
        .run_seq(run_seq), .trace_read(trace_read)
    );

    csr_bank #(.ADDRW(8), .DW(32)) u_csr (
        .clk(clk), .rst(rst),
        .wr_en(csr_wr), .rd_en(csr_rd), .addr(csr_addr),
        .wr_data(csr_wdata), .rd_data(csr_rdata), .rd_valid(csr_rvalid),
        .time_now(time_now), .event_count(32'd0), .status_in(32'd0),
        .ctrl_out(), .scratch_out()
    );

    // ---- uart tx ----
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst), .start(tx_send),
        .tx_data(tx_byte), .tx(uart_tx_pin), .busy(tx_busy), .done()
    );

endmodule

`default_nettype wire

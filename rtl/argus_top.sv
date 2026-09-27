// ============================================================================
// argus_top.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Full ARGUS instrument top level. Composes every subsystem into one design:
//     - Control plane : UART <-> command_router <-> csr_bank <-> UART, timebase
//     - Capture        : monitors -> event_logger -> trace_buffer + trigger
//     - Sequencer      : test_sequencer executing programmed steps
//     - Fault          : safety_interlock gating fault_controller
//
//   This is the module a synthesis flow would target. Its testbench proves the
//   subsystems are wired together correctly; each subsystem's behavior is
//   already proven by its own bench.
//
// Interface (board-facing):
//   clk, rst                         : system clock / reset
//   uart_rx_pin / uart_tx_pin        : host serial link
//   gpio_in / dut_rst_in / dut_clk_in: DUT observation inputs
//   dut_reset_out / bus_suppress / clk_en_out : fault outputs to DUT
//   heartbeat                        : liveness LED
//
// Design tradeoff:
//   Pure structural composition keeps the top testable and keeps all behavior
//   in verified leaf modules.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"
`include "argus_seq_ops.svh"

module argus_top #(
    parameter int CLKS_PER_BIT = 434,
    parameter int TRACE_AW     = 8,
    parameter int SEQ_AW       = 6
) (
    input  wire clk,
    input  wire rst,

    input  wire uart_rx_pin,
    output wire uart_tx_pin,

    input  wire gpio_in,
    input  wire dut_rst_in,
    input  wire dut_clk_in,

    output wire dut_reset_out,
    output wire bus_suppress,
    output wire clk_en_out,

    output wire heartbeat
);

    // ---- timebase (shared) ----
    wire [63:0] time_now;
    timebase #(.WIDTH(64)) u_time (
        .clk(clk), .rst(rst), .en(1'b1), .time_now(time_now), .tick()
    );
    assign heartbeat = time_now[23];

    // ---- control plane: UART rx -> router -> csr -> UART tx ----
    wire [7:0] rx_byte; wire rx_valid, rx_ferr;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .rx(uart_rx_pin),
        .rx_data(rx_byte), .data_valid(rx_valid), .frame_error(rx_ferr)
    );

    wire        csr_wr, csr_rd;
    wire [7:0]  csr_addr;
    wire [31:0] csr_wdata, csr_rdata;
    wire        csr_rvalid;
    wire [7:0]  tx_byte;  wire tx_send, tx_busy;
    wire        run_seq, trace_read_cmd;

    command_router u_cmd (
        .clk(clk), .rst(rst),
        .rx_byte(rx_byte), .rx_valid(rx_valid),
        .csr_wr(csr_wr), .csr_rd(csr_rd), .csr_addr(csr_addr),
        .csr_wdata(csr_wdata), .csr_rdata(csr_rdata), .csr_rvalid(csr_rvalid),
        .tx_byte(tx_byte), .tx_send(tx_send), .tx_busy(tx_busy),
        .run_seq(run_seq), .trace_read(trace_read_cmd)
    );

    wire [31:0] event_count_bus;
    csr_bank #(.ADDRW(8), .DW(32)) u_csr (
        .clk(clk), .rst(rst),
        .wr_en(csr_wr), .rd_en(csr_rd), .addr(csr_addr),
        .wr_data(csr_wdata), .rd_data(csr_rdata), .rd_valid(csr_rvalid),
        .time_now(time_now), .event_count(event_count_bus), .status_in(32'd0),
        .ctrl_out(), .scratch_out()
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst), .start(tx_send),
        .tx_data(tx_byte), .tx(uart_tx_pin), .busy(tx_busy), .done()
    );

    // ---- capture subsystem ----
    wire        overflow, triggered;
    capture_subsystem #(.TRACE_AW(TRACE_AW)) u_cap (
        .clk(clk), .rst(rst),
        .gpio_in(gpio_in), .dut_rst_in(dut_rst_in), .dut_clk_in(dut_clk_in),
        .arm(run_seq), .match_src(`SRC_RESET), .match_code(`EVC_RST_ASSERT),
        .post_count(16'd8),
        .rd_en(1'b0), .rd_data(), .rd_valid(),
        .event_count(event_count_bus), .overflow(overflow), .triggered(triggered)
    );

    // ---- sequencer with its own program memory ----
    wire [SEQ_AW-1:0] seq_pc;
    reg  [47:0]       seq_mem [0:(1<<SEQ_AW)-1];
    wire [47:0]       seq_instr = seq_mem[seq_pc];
    // Default program: END (host/board can preload a real program).
    integer gi;
    initial begin
        for (gi = 0; gi < (1<<SEQ_AW); gi = gi + 1) seq_mem[gi] = {`OP_END, 8'd0, 32'd0};
    end

    wire        seq_csr_wr, seq_csr_rd;
    wire [7:0]  seq_csr_addr;
    wire [31:0] seq_csr_wdata;
    wire        seq_inject_req;
    wire [7:0]  seq_inject_mask;
    wire        seq_busy, seq_done, seq_failed;
    wire [SEQ_AW-1:0] seq_fail_pc;

    test_sequencer #(.AW(SEQ_AW)) u_seq (
        .clk(clk), .rst(rst), .start(run_seq),
        .pc(seq_pc), .instr(seq_instr),
        .csr_wr(seq_csr_wr), .csr_rd(seq_csr_rd), .csr_addr(seq_csr_addr),
        .csr_wdata(seq_csr_wdata), .csr_rdata(csr_rdata), .csr_rvalid(csr_rvalid),
        .ev_valid(1'b0), .ev_code(8'd0),
        .inject_req(seq_inject_req), .inject_mask(seq_inject_mask),
        .busy(seq_busy), .done(seq_done), .failed(seq_failed), .fail_pc(seq_fail_pc)
    );

    // ---- fault subsystem: interlock gates the controller ----
    wire        fault_active;
    safety_interlock u_ilk (
        .clk(clk), .rst(rst), .global_en(1'b1),
        .arm(seq_inject_req), .disarm(~seq_inject_req), .fire(seq_inject_req),
        .duration(16'd16), .max_duration(16'd64),
        .fault_active(fault_active), .time_left(), .armed(), .violation()
    );

    fault_controller u_fc (
        .clk(clk), .rst(rst),
        .fault_active(fault_active), .fault_type(3'd1), // reset-pulse default
        .corrupt_mask(32'd0), .data_in(32'd0),
        .data_out(), .dut_reset_out(dut_reset_out),
        .bus_suppress(bus_suppress), .clk_en_out(clk_en_out)
    );

endmodule

`default_nettype wire

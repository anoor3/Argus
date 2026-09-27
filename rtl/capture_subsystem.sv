// ============================================================================
// capture_subsystem.sv
// ----------------------------------------------------------------------------
// Purpose:
//   P2 event-capture datapath, wired together: three monitors feed the
//   event_logger, whose records go into the trace_buffer; the trigger_engine
//   watches the logged stream and freezes capture on a programmed condition.
//   The timebase supplies one correlation clock for every event.
//
//   gpio/reset/clock monitors -> event_logger -(records)-> trace_buffer
//                                     ^ en                     ^
//                              trigger_engine (freezes en, watches stream)
//
// Interface:
//   clk, rst                : clock / sync reset
//   gpio_in/dut_rst_in/dut_clk_in : DUT observation inputs (async)
//   arm, match_src, match_code, post_count : trigger config
//   rd_en                   : pop a record toward the host
//   rd_data[95:0], rd_valid : record readout
//   event_count[31:0]       : events logged
//   overflow                : trace overflow flag
//   triggered               : trigger fired since arm
//
// Design tradeoff:
//   Structural composition of already-verified blocks; this level's test only
//   proves the wiring and the timestamp correlation across sources.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_events.svh"

module capture_subsystem #(
    parameter int TRACE_AW = 8
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        gpio_in,
    input  wire        dut_rst_in,
    input  wire        dut_clk_in,

    input  wire        arm,
    input  wire [7:0]  match_src,
    input  wire [7:0]  match_code,
    input  wire [15:0] post_count,

    input  wire        rd_en,
    output wire [95:0] rd_data,
    output wire        rd_valid,
    output wire [31:0] event_count,
    output wire        overflow,
    output wire        triggered
);

    // ---- timebase ----
    wire [63:0] time_now;
    timebase #(.WIDTH(64)) u_time (
        .clk(clk), .rst(rst), .en(1'b1), .time_now(time_now), .tick()
    );

    // ---- monitors ----
    wire        g_v, r_v, c_v;
    wire [7:0]  g_c, r_c, c_c;
    wire [15:0] g_val, r_val, c_val;

    gpio_monitor u_gpio (
        .clk(clk), .rst(rst), .gpio_in(gpio_in), .debounce_cyc(8'd0),
        .ev_valid(g_v), .ev_code(g_c), .ev_value(g_val)
    );
    reset_monitor u_reset (
        .clk(clk), .rst(rst), .dut_rst_in(dut_rst_in),
        .ev_valid(r_v), .ev_code(r_c), .ev_value(r_val)
    );
    clock_monitor u_clock (
        .clk(clk), .rst(rst), .dut_clk_in(dut_clk_in),
        .window_cyc(16'd50), .min_edges(16'd2),
        .ev_valid(c_v), .ev_code(c_c), .ev_value(c_val)
    );

    // ---- trigger engine ----
    wire capture_en;
    wire log_wr;
    wire [95:0] log_data;
    // trigger watches the logger's write strobe/fields
    trigger_engine u_trig (
        .clk(clk), .rst(rst), .arm(arm),
        .match_src(match_src), .match_code(match_code), .post_count(post_count),
        .ev_valid(log_wr), .ev_src(log_data[31:24]), .ev_code(log_data[23:16]),
        .capture_en(capture_en), .triggered(triggered), .trig_pulse()
    );

    // ---- event logger ----
    wire [31:0] drop_count;
    event_logger u_log (
        .clk(clk), .rst(rst), .en(capture_en), .time_now(time_now),
        .src0_valid(g_v), .src0_id(`SRC_GPIO),  .src0_code(g_c), .src0_value(g_val),
        .src1_valid(r_v), .src1_id(`SRC_RESET), .src1_code(r_c), .src1_value(r_val),
        .src2_valid(c_v), .src2_id(`SRC_CLOCK), .src2_code(c_c), .src2_value(c_val),
        .rec_wr(log_wr), .rec_data(log_data),
        .event_count(event_count), .drop_count(drop_count)
    );

    // ---- trace buffer ----
    wire full, empty;
    trace_buffer #(.DW(96), .AW(TRACE_AW)) u_trace (
        .clk(clk), .rst(rst),
        .wr_en(log_wr), .wr_data(log_data),
        .rd_en(rd_en), .rd_data(rd_data), .rd_valid(rd_valid),
        .count(), .overflow(overflow), .full(full), .empty(empty)
    );

endmodule

`default_nettype wire

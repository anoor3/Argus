// ============================================================================
// argus_events.svh -- shared event record format and source/code IDs
//
// Every monitor emits an event described by (source_id, event_code, value).
// The event_logger stamps it with the 64-bit timebase value and packs it into
// a fixed-width record written to the trace buffer.
//
// Record layout (96 bits): { timestamp[63:0], source_id[7:0], code[7:0], value[15:0] }
// ============================================================================
`ifndef ARGUS_EVENTS_SVH
`define ARGUS_EVENTS_SVH

// Field widths
`define EV_SRC_W   8
`define EV_CODE_W  8
`define EV_VAL_W   16
`define EV_TS_W    64
`define EV_REC_W   (`EV_TS_W + `EV_SRC_W + `EV_CODE_W + `EV_VAL_W) // 96

// Source IDs (who produced the event)
`define SRC_GPIO   8'h01
`define SRC_RESET  8'h02
`define SRC_CLOCK  8'h03

// Event codes (what happened)
`define EVC_RISE       8'h01  // rising edge
`define EVC_FALL       8'h02  // falling edge
`define EVC_RST_ASSERT 8'h10  // reset asserted
`define EVC_RST_DEASSRT 8'h11 // reset deasserted
`define EVC_CLK_LOST   8'h20  // clock activity missing
`define EVC_CLK_OK     8'h21  // clock activity restored

// Pack/unpack helpers
`define EV_PACK(ts, src, code, val) { ts, src, code, val }

`endif

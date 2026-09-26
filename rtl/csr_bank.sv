// ============================================================================
// csr_bank.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Memory-mapped Control/Status Register file. The single point where the host
//   (via command_router) reads and writes configuration and observes status.
//   Read-only status registers are driven by hardware inputs; read/write config
//   registers are owned by the host.
//
// Interface:
//   clk, rst              : clock / synchronous active-high reset
//   wr_en                 : pulse to write wr_data into register at addr
//   rd_en                 : pulse to latch a read (rd_data valid next cycle)
//   addr   [ADDRW-1:0]    : register address
//   wr_data[DW-1:0]       : write payload
//   rd_data[DW-1:0]       : read result (registered, valid the cycle after rd_en)
//   rd_valid              : 1-cycle strobe marking rd_data valid
//   -- hardware status inputs (RO registers) --
//   time_now[63:0]        : timebase snapshot for TIME_LO/TIME_HI
//   event_count[DW-1:0]   : events captured (from event_logger)
//   status_in[DW-1:0]     : status flags (busy/done/error)
//   -- config outputs (RW registers) --
//   ctrl_out[DW-1:0]      : CTRL register value driven to the rest of ARGUS
//   scratch_out[DW-1:0]   : SCRATCH register (loopback/self-test)
//
// State / cycle behavior:
//   - Writes to RW registers take effect on the next clock.
//   - Writes to RO addresses are ignored (no effect), by design.
//   - Reads are registered: assert rd_en with addr, rd_data+rd_valid appear the
//     following cycle. This keeps the read mux out of the host's timing path.
//
// Edge/error cases:
//   - Simultaneous rd_en and wr_en to the same RW addr: write wins for stored
//     state; the read returns the pre-write (old) value (read-before-write),
//     which the TB verifies so behavior is defined, not accidental.
//   - Unknown/reserved addr read: returns 0.
//
// Design tradeoff:
//   A flat addressed register file (vs. bespoke wires per block) gives the host
//   a uniform access model and makes command_router trivial. Cost is a read mux
//   whose width grows with register count; registered reads keep it timing-safe.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"

module csr_bank #(
    parameter int ADDRW = 8,
    parameter int DW    = 32
) (
    input  wire              clk,
    input  wire              rst,

    input  wire              wr_en,
    input  wire              rd_en,
    input  wire [ADDRW-1:0]  addr,
    input  wire [DW-1:0]     wr_data,
    output reg  [DW-1:0]     rd_data,
    output reg               rd_valid,

    input  wire [63:0]       time_now,
    input  wire [DW-1:0]     event_count,
    input  wire [DW-1:0]     status_in,

    output wire [DW-1:0]     ctrl_out,
    output wire [DW-1:0]     scratch_out
);

    // Frozen register addresses (see docs/REQUIREMENTS.md)
    localparam [ADDRW-1:0] ADDR_ID          = 8'h00;
    localparam [ADDRW-1:0] ADDR_SCRATCH     = 8'h01;
    localparam [ADDRW-1:0] ADDR_CTRL        = 8'h02;
    localparam [ADDRW-1:0] ADDR_STATUS      = 8'h03;
    localparam [ADDRW-1:0] ADDR_TIME_LO     = 8'h04;
    localparam [ADDRW-1:0] ADDR_TIME_HI     = 8'h05;
    localparam [ADDRW-1:0] ADDR_EVENT_COUNT = 8'h06;

    localparam [DW-1:0] MAGIC_ID = 32'hA2_60_01_01;  // "ARGUS" id constant

    reg [DW-1:0] scratch_r;
    reg [DW-1:0] ctrl_r;

    assign scratch_out = scratch_r;
    assign ctrl_out    = ctrl_r;

    // Write path: only RW registers accept writes.
    always @(posedge clk) begin
        if (rst) begin
            scratch_r <= '0;
            ctrl_r    <= '0;
        end else if (wr_en) begin
            case (addr)
                ADDR_SCRATCH: scratch_r <= wr_data;
                ADDR_CTRL:    ctrl_r    <= wr_data;
                default:      ; // RO or reserved: ignore
            endcase
        end
    end

    // Read path: registered read-before-write.
    always @(posedge clk) begin
        if (rst) begin
            rd_data  <= '0;
            rd_valid <= 1'b0;
        end else begin
            rd_valid <= rd_en;
            if (rd_en) begin
                case (addr)
                    ADDR_ID:          rd_data <= MAGIC_ID;
                    ADDR_SCRATCH:     rd_data <= scratch_r;
                    ADDR_CTRL:        rd_data <= ctrl_r;
                    ADDR_STATUS:      rd_data <= status_in;
                    ADDR_TIME_LO:     rd_data <= time_now[31:0];
                    ADDR_TIME_HI:     rd_data <= time_now[63:32];
                    ADDR_EVENT_COUNT: rd_data <= event_count;
                    default:          rd_data <= '0;
                endcase
            end
        end
    end

endmodule

`default_nettype wire

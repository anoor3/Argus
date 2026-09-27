// ============================================================================
// test_sequencer.sv
// ----------------------------------------------------------------------------
// Purpose:
//   Programmable micro-sequencer that executes a deterministic list of
//   validation steps in hardware: write registers, read-and-expect, wait for an
//   event, delay, and assert/clear a fault-injection request. This lets a whole
//   bring-up test run identically every time without host timing jitter.
//
// Instruction (48b): { opcode[7:0], addr[7:0], operand[31:0] } (see ops svh)
//
// Interface:
//   clk, rst              : clock / sync reset
//   start                 : begin executing at program counter 0
//   -- program memory (loaded by TB/host) --
//   instr[47:0]           : instruction at the current pc (comb read)
//   pc[AW-1:0]            : program counter to the memory
//   -- CSR access --
//   csr_wr, csr_rd, csr_addr, csr_wdata, csr_rdata, csr_rvalid
//   -- events --
//   ev_valid, ev_code     : from event_logger, for WAIT_EVENT
//   -- fault --
//   inject_req, inject_mask
//   -- status --
//   busy, done, failed, fail_pc
//
// Behavior / cycle:
//   FETCH -> DECODE/EXEC -> advance pc. READ_EXPECT issues csr_rd, waits for
//   rvalid, compares. WAIT_EVENT blocks until a matching event or a timeout
//   (fails). END sets done. Any failed check sets failed + fail_pc and stops.
//
// Edge/error cases:
//   - WAIT_EVENT timeout -> failed (no infinite hang).
//   - READ_EXPECT mismatch -> failed with the offending pc captured.
//
// Design tradeoff:
//   A tiny fixed-width ISA (vs. a general CPU) is enough for deterministic test
//   scripting and is trivially verifiable, which is the whole point.
// ============================================================================
`default_nettype none
`include "argus_timescale.svh"
`include "argus_seq_ops.svh"

module test_sequencer #(
    parameter int AW = 6,                 // program address width
    parameter int WAIT_TIMEOUT = 100000   // cycles before WAIT_EVENT fails
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    output reg  [AW-1:0] pc,
    input  wire [47:0]   instr,

    output reg         csr_wr,
    output reg         csr_rd,
    output reg  [7:0]  csr_addr,
    output reg  [31:0] csr_wdata,
    input  wire [31:0] csr_rdata,
    input  wire        csr_rvalid,

    input  wire        ev_valid,
    input  wire [7:0]  ev_code,

    output reg         inject_req,
    output reg  [7:0]  inject_mask,

    output reg         busy,
    output reg         done,
    output reg         failed,
    output reg [AW-1:0] fail_pc
);

    localparam [2:0] S_IDLE=0, S_FETCH=1, S_EXEC=2, S_RWAIT=3,
                     S_WAITEV=4, S_DELAY=5, S_HALT=6;

    reg [2:0]  state;
    reg [31:0] timer;

    wire [7:0]  op      = instr[47:40];
    wire [7:0]  a_field = instr[39:32];
    wire [31:0] operand = instr[31:0];

    always @(posedge clk) begin
        if (rst) begin
            state<=S_IDLE; pc<=0; csr_wr<=0; csr_rd<=0; csr_addr<=0; csr_wdata<=0;
            inject_req<=0; inject_mask<=0; busy<=0; done<=0; failed<=0; fail_pc<=0;
            timer<=0;
        end else begin
            csr_wr <= 1'b0; csr_rd <= 1'b0;
            case (state)
                S_IDLE: begin
                    done<=1'b0; busy<=1'b0;
                    if (start) begin
                        pc<=0; failed<=1'b0; busy<=1'b1; state<=S_FETCH;
                    end
                end
                S_FETCH: state <= S_EXEC;   // instr is a comb read of mem[pc]
                S_EXEC: begin
                    case (op)
                        `OP_END: begin done<=1'b1; busy<=1'b0; state<=S_HALT; end
                        `OP_WRITE: begin
                            csr_addr<=a_field; csr_wdata<=operand; csr_wr<=1'b1;
                            pc<=pc+1'b1; state<=S_FETCH;
                        end
                        `OP_READ_EXPECT: begin
                            csr_addr<=a_field; csr_rd<=1'b1; state<=S_RWAIT;
                        end
                        `OP_WAIT_EVENT: begin
                            timer<=0; state<=S_WAITEV;
                        end
                        `OP_DELAY: begin
                            timer<=operand; state<=S_DELAY;
                        end
                        `OP_INJECT: begin
                            inject_req<=1'b1; inject_mask<=operand[7:0];
                            pc<=pc+1'b1; state<=S_FETCH;
                        end
                        `OP_CLEAR: begin
                            inject_req<=1'b0;
                            pc<=pc+1'b1; state<=S_FETCH;
                        end
                        default: begin // unknown op: fail safe
                            failed<=1'b1; fail_pc<=pc; done<=1'b1; busy<=1'b0;
                            state<=S_HALT;
                        end
                    endcase
                end
                S_RWAIT: if (csr_rvalid) begin
                    if (csr_rdata !== operand) begin
                        failed<=1'b1; fail_pc<=pc; done<=1'b1; busy<=1'b0;
                        state<=S_HALT;
                    end else begin
                        pc<=pc+1'b1; state<=S_FETCH;
                    end
                end
                S_WAITEV: begin
                    if (ev_valid && (ev_code == a_field)) begin
                        pc<=pc+1'b1; state<=S_FETCH;
                    end else if (timer >= WAIT_TIMEOUT) begin
                        failed<=1'b1; fail_pc<=pc; done<=1'b1; busy<=1'b0;
                        state<=S_HALT;
                    end else timer<=timer+1'b1;
                end
                S_DELAY: begin
                    if (timer <= 1) begin pc<=pc+1'b1; state<=S_FETCH; end
                    else timer<=timer-1'b1;
                end
                S_HALT: begin
                    // stay halted; re-arm via start (handled in S_IDLE only)
                    if (start) begin pc<=0; failed<=0; busy<=1; state<=S_FETCH; done<=0; end
                end
                default: state<=S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire

// ============================================================================
// argus_seq_ops.svh -- test_sequencer instruction encoding
//
// Each instruction is a fixed 48-bit word:
//   { opcode[7:0], addr[7:0], operand[31:0] }
//
// The sequencer executes a small program of these to run deterministic,
// repeatable validation steps without host intervention.
// ============================================================================
`ifndef ARGUS_SEQ_OPS_SVH
`define ARGUS_SEQ_OPS_SVH

`define SEQ_INSTR_W 48

// opcodes
`define OP_END         8'h00  // stop, assert done
`define OP_WRITE       8'h01  // csr[addr] <= operand
`define OP_READ_EXPECT 8'h02  // fail unless csr[addr] == operand
`define OP_WAIT_EVENT  8'h03  // wait until ev_valid with code==addr (timeout->fail)
`define OP_DELAY       8'h04  // wait operand cycles
`define OP_INJECT      8'h05  // raise inject_req with mask=operand[7:0]
`define OP_CLEAR       8'h06  // drop inject_req

`endif

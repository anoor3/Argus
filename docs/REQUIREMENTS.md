# ARGUS Requirements & Interface Table (P0)

This document freezes the assumptions that the RTL depends on. No hidden
assumption may live only in the RTL; it must be recorded here first.

## Target platform (simulation-first)

ARGUS is developed and verified **simulation-first** using Icarus Verilog
(`iverilog -g2012`). All RTL is kept in the synthesizable SystemVerilog subset
so it can later target a real FPGA without rewrites. The reference board
assumptions below are the intended synthesis target; they do not block
simulation.

| Item                 | Assumption (reference target)                     |
|----------------------|---------------------------------------------------|
| FPGA family          | Lattice iCE40 / Xilinx Artix-7 class (7-series)   |
| System clock `clk`   | 50 MHz (20 ns period) nominal                     |
| Reset `rst`          | Synchronous, active-high, held >= 4 cycles        |
| Host link            | UART, 8-N-1, default 115200 baud                  |
| DUT I/O voltage      | 3.3 V LVCMOS only                                 |
| Analog signals       | Never direct to FPGA pins; via sensor IC over I2C |

## Clock / reset contract

- Single primary clock domain `clk` for the control plane and datapath.
- Asynchronous DUT inputs cross into `clk` **only** through `cdc_sync` /
  `async_fifo`. Raw async multi-bit signals are never sampled directly.
- `rst` is synchronous, active-high. Every stateful block returns to a defined
  benign state on reset.

## Register map (CSR, 8-bit address / 32-bit data) — initial freeze

| Addr | Name           | Access | Purpose                                  |
|------|----------------|--------|------------------------------------------|
| 0x00 | ID             | RO     | Constant magic ID for host handshake     |
| 0x01 | SCRATCH        | RW     | Read/write test register                 |
| 0x02 | CTRL           | RW     | Global enable / start bits               |
| 0x03 | STATUS         | RO     | Busy / done / error flags                |
| 0x04 | TIME_LO        | RO     | Timebase counter [31:0]                  |
| 0x05 | TIME_HI        | RO     | Timebase counter [63:32]                 |
| 0x06 | EVENT_COUNT    | RO     | Events captured                          |
| 0x07 | TRACE_RDATA    | RO     | Trace buffer read data (pop)             |

Additional registers are appended per phase and recorded here when added.

## Command protocol (host <-> command_router) — initial freeze

Each host command is a fixed frame over UART bytes:

```
[CMD][ADDR][DATA3][DATA2][DATA1][DATA0]
```

- `CMD`  : 0x01=WRITE_REG, 0x02=READ_REG, 0x03=TRACE_READ, 0x04=RUN_SEQ
- `ADDR` : CSR address (8-bit)
- `DATA` : 32-bit big-endian payload (write only; ignored for reads)

Read responses return 4 data bytes big-endian. This framing is verified in the
`command_router` testbench.

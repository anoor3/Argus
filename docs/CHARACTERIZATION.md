# ARGUS Characterization (P8)

All numbers below are either (a) design parameters fixed in RTL, or (b)
observed from the self-checking simulations in `tb/`. This is a simulation-first
instrument; where a figure would require silicon (e.g. post-route Fmax), it is
marked as **not yet measured** rather than invented, per the project rules.

## Method

- Simulator: Icarus Verilog 13.0 (`iverilog -g2012`).
- Reference clock: 50 MHz assumed (20 ns period). Testbenches use a 20 ns clock
  (`always #10 clk = ~clk`).
- Evidence: run `./scripts/regression.sh` from a clean checkout; every figure
  citing a testbench is reproducible there.

## Timestamp resolution and rollover

- Source: `timebase.sv`, `WIDTH = 64`.
- Resolution: **1 cycle = 20 ns** at 50 MHz.
- Rollover: 2^64 cycles ≈ 1.17e13 s ≈ **~370,000 years**; not reachable in
  operation. Rollover correctness is instead proven on a narrow instance
  (`timebase_tb` uses `WIDTH = 8`, wraps at 256) so the wrap arithmetic is
  verified without an impractically long run.

## Trace buffer depth and record width

- Record width: **96 bits** = `{ timestamp[63:0], source[7:0], code[7:0],
  value[15:0] }` (`rtl/argus_events.svh`, `EV_REC_W`).
- Default depth: `trace_buffer` `AW = 8` -> **256 records** (2^8), i.e.
  256 x 96 bits = **3 KB** of trace storage. Depth is a parameter; `argus_top`
  instances it with `TRACE_AW = 8`.
- Overflow behavior: circular overwrite-oldest with a **sticky overflow flag**
  so loss is always visible (verified in `trace_buffer_tb`, overflow case).

## Event handling limits

- One record is written to the trace buffer per cycle.
- Simultaneous events from multiple monitors are serialized through a 1-deep
  skid in `event_logger`; a collision that exceeds the skid increments
  `drop_count` (verified path in `event_logger_tb`). Maximum sustained logged
  event rate is therefore **1 event/cycle = 50 M events/s** at 50 MHz, with
  simultaneous bursts of 2 handled without loss.

## Control-plane throughput

- UART default: 8-N-1 @ 115200 baud -> ~11.5 KB/s raw, ~1920 command frames/s
  (6 bytes/frame). Simulated with a small `CLKS_PER_BIT` for speed; framing and
  loopback verified in `uart_tx_tb`, `uart_rx_tb`, `uart_loopback_tb`.
- End-to-end register round-trip (write then read over real UART, full control
  plane) completes in the `argus_core_tb` run that finishes at
  **42,150 ns of sim time** for two reads + one write at `CLKS_PER_BIT = 8`.

## Protocol exercisers

- SPI: `spi_master` SCLK half-period = `(clk_div+1)` system clocks; configured
  vs actual rate is exact by construction (verified in `spi_master_tb`, mode 0).
- I2C: `i2c_master` SCL quarter-period = `clk_div` system clocks; single-byte
  write with ACK/NACK verified in `i2c_master_tb`.
- ADC: `adc_bridge` assembles a 12-bit sample from two SPI bytes
  (`adc_bridge_tb`).

## Fault timing accuracy

- Fault width is bounded by `safety_interlock` `duration` and verified to be
  **exact to the cycle**: `safety_interlock_tb` checks `fault_active` is high
  for exactly `duration` cycles; `fault_controller_tb` checks `dut_reset_out`
  asserts for exactly `duration` cycles (accounting for the 1-cycle output
  register).
- Recovery latency after a fault: **1 cycle** (outputs are registered; the
  cycle after `fault_active` drops, all outputs are benign).

## Event-to-trigger latency

- `trigger_engine` evaluates the match combinationally on the logged event and
  registers the decision, giving a **1-cycle** event-to-trigger latency
  (verified in `trigger_engine_tb`; freeze-on-match with `post_count = 0`).

## Not yet measured (requires hardware/synthesis)

- FPGA LUT/FF/BRAM utilization.
- Post-route maximum clock frequency and timing slack.
- Physical UART/USB throughput on a real link.

These are intentionally left unmeasured rather than estimated. They become
available once the design is run through an FPGA toolchain on the target board.

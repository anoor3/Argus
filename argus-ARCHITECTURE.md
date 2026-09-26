# ARGUS Architecture

## Project thesis
ARGUS turns an FPGA into a deterministic hardware validation instrument that can observe, stimulate, perturb, and timestamp a device under test (DUT). It is designed to make board bring-up repeatable instead of depending on ad-hoc manual probing.

## Module map

### `timebase.sv`
Free-running cycle/time counter used by every event source so independent monitors can be correlated.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `csr_bank.sv`
Memory-mapped configuration/status registers for thresholds, enables, test parameters, counters, and results.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `command_router.sv`
Decodes host commands and routes register access, test-start commands, trace reads, and fault-control requests.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `test_sequencer.sv`
Programmable FSM/micro-sequencer that executes deterministic validation steps with timeout and branching.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `event_logger.sv`
Normalizes events from monitors into a common record format and arbitrates writes into the trace buffer.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `trace_buffer.sv`
BRAM-backed circular/event buffer storing timestamp, source ID, event code, metadata, and sampled value.

**You must understand:** Know record/counter width, overflow behavior, timestamp basis, simultaneous-event handling, and how measurement overhead can bias results.

### `trigger_engine.sv`
Evaluates trigger conditions such as edge, threshold, sequence, or timeout and freezes/marks trace regions.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `clock_monitor.sv`
Counts or measures external clock activity and detects missing/out-of-range clocks.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `reset_monitor.sv`
Tracks reset assertion/deassertion timing and validates ordering relative to other signals.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `gpio_monitor.sv`
Captures edges, pulse widths, state changes, and optional debounce/qualification.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `i2c_master.sv`
Performs scripted I2C transactions and reports ACK/NACK, timeout, arbitration/error status.

**You must understand:** Know the electrical/logical framing, timing parameters, error states, timeout behavior, and how the controller is verified against known transactions.

### `spi_master.sv`
Performs configurable SPI transfers with mode/clock divider controls and response checking.

**You must understand:** Know the electrical/logical framing, timing parameters, error states, timeout behavior, and how the controller is verified against known transactions.

### `uart_rx.sv / uart_tx.sv`
Host/DUT serial communication with framing-error and timeout handling.

**You must understand:** Know the electrical/logical framing, timing parameters, error states, timeout behavior, and how the controller is verified against known transactions.

### `adc_bridge.sv`
Reads external voltage/current/temperature sensors through I2C/SPI rather than exposing analog signals directly to FPGA pins.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `fault_controller.sv`
Applies bounded, explicitly enabled faults such as reset pulse, bus-response suppression, controlled data corruption, or safe clock enable manipulation.

**You must understand:** Explain where the fault is inserted, how duration/mask is controlled, how safety is enforced, and how you prove the injected failure is exactly the one intended.

### `safety_interlock.sv`
Prevents unsafe or contradictory injection requests; requires arm/enable conditions and automatically returns outputs to a benign state.

**You must understand:** Know its inputs/outputs, state, cycle-level behavior, reset behavior, error cases, verification strategy, and the design tradeoff that justifies having this block.

### `cdc_sync.sv / async_fifo.sv`
Handles asynchronous DUT signals or multiple clock domains without metastability being treated as valid data.

**You must understand:** Know the source/destination clock domains, why direct multi-bit synchronization is unsafe, how full/empty or handshake logic is generated, and what failure metastability could cause.


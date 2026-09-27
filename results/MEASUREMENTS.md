# ARGUS Measurements Summary

Condensed results table. Full methodology is in `docs/CHARACTERIZATION.md`;
raw evidence is `results/regression_log.txt` (regenerate with
`./scripts/regression.sh`).

| Metric                        | Value                        | Source / evidence            |
|-------------------------------|------------------------------|------------------------------|
| Timestamp resolution          | 20 ns (1 cycle @ 50 MHz)     | timebase.sv (WIDTH=64)       |
| Timestamp rollover            | ~370,000 years (2^64)        | timebase_tb (wrap on W=8)    |
| Trace record width            | 96 bits                      | argus_events.svh EV_REC_W    |
| Trace depth (default)         | 256 records (2^8) = 3 KB     | trace_buffer AW=8            |
| Max logged event rate         | 1 event/cycle = 50 M/s       | event_logger_tb              |
| Simultaneous events handled   | 2 (via 1-deep skid)          | event_logger_tb              |
| Event-to-trigger latency      | 1 cycle                      | trigger_engine_tb            |
| Fault width accuracy          | exact to the cycle           | safety_interlock_tb, fault_* |
| Fault recovery latency        | 1 cycle (registered restore) | fault_controller_tb          |
| RTL testbenches passing       | 36                           | scripts/regression.sh        |
| Host unit tests passing       | 32                           | host/tests                   |

## Not yet measured (needs FPGA synthesis)

- LUT/FF/BRAM utilization
- Post-route Fmax and timing slack
- Physical UART throughput on a real link

These are deliberately not estimated; they require a synthesis/place-and-route
run on the target board.

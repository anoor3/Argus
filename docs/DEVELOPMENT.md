# Development workflow

How to work on ARGUS and keep the regression green.

## Prerequisites

- `iverilog` (Icarus Verilog) — RTL simulation.
- `python3` (3.8+) — host tooling and its tests. No external Python deps.

## Directory conventions

- RTL lives in `rtl/`, one module per file, `snake_case.sv`.
- Every RTL module `foo.sv` has a testbench `tb/foo_tb.sv` whose top module is
  `foo_tb`. Extra corner-case benches use the `foo_edge_tb.sv` convention.
- Shared RTL headers: `rtl/argus_timescale.svh`, `rtl/argus_events.svh`,
  `rtl/argus_seq_ops.svh`.
- Shared TB macros: `tb/argus_check.svh`
  (`CHECK`, `CHECK_EQ`, `FINISH_REPORT`, `WATCHDOG`).

## Testbench rules

- Self-checking only: print `TEST PASSED` on success, `TEST FAILED` otherwise.
- Always arm a watchdog: `` `WATCHDOG(<time_units>) `` so a bug can never hang
  the run. The Makefile also wall-clock-kills any sim after `SIM_TIMEOUT` s.
- When a protocol master/slave *model* in a bench misbehaves, isolate the RTL
  with a deterministic stub before suspecting the RTL.

## Common commands

```
make <name>        # build + run tb/<name>_tb.sv
make all           # run every testbench
make clean         # remove sim/build artifacts
./scripts/regression.sh          # RTL + host tests, single verdict
cd host && python3 -m unittest discover -s tests
```

## Commit style

`type(scope): summary`, one logical unit per commit (e.g. RTL and its testbench
are separate commits). Keep each commit build-green.

# ARGUS

ARGUS turns an FPGA into a deterministic hardware validation instrument that can
observe, stimulate, perturb, and timestamp a device under test (DUT). It makes
board bring-up repeatable instead of depending on ad-hoc manual probing.

Built simulation-first: every RTL block has a self-checking testbench, and the
whole design plus host tooling passes a one-command regression.

## What it does

- **Observe**: GPIO/reset/clock monitors emit timestamped events onto one shared
  64-bit timebase, logged into a circular trace buffer with overflow tracking.
- **Stimulate**: SPI, I2C, and UART masters plus an ADC/sensor bridge exercise a
  DUT with scripted transactions.
- **Sequence**: a programmable micro-sequencer runs deterministic
  WRITE/READ_EXPECT/WAIT_EVENT/DELAY/INJECT/CLEAR/END steps in hardware.
- **Perturb (safely)**: a fault controller applies bounded digital faults, gated
  by a hardware safety interlock (two-step arm/fire, duration cap, auto-restore).
- **Trigger**: a trigger engine freezes the trace on a matched event with a
  configurable post-trigger window.
- **Automate**: a stdlib-only Python host runs JSON test plans, decodes traces,
  and exports JSON/CSV reports with pass/fail summaries.

## Repository layout

```
rtl/     SystemVerilog RTL (synthesizable subset) + shared headers
tb/      self-checking testbenches (one per module) + shared check macros
host/    Python host package (protocol, client, plan runner, reporting, CLI)
docs/    requirements, safety boundary, characterization, architecture diagram
scripts/ regression runner
results/ preserved evidence (regression log)
sim/     build artifacts (gitignored)
```

## Quick start

Prerequisites: `iverilog` (Icarus Verilog) and `python3`.

```
# Full regression: RTL testbenches + host unit tests
./scripts/regression.sh

# Run a single RTL testbench
make timebase

# Run the host tooling against the built-in mock instrument
cd host && python3 -m argus.cli run --plan plans/smoke.json --mock
```

## Verification

- 36 RTL self-checking testbenches (`make all` or the regression script).
- Host unit tests: `cd host && python3 -m unittest discover -s tests`.
- Every testbench prints `TEST PASSED`/`TEST FAILED` and arms a watchdog so a
  bad run fails fast instead of hanging.

## Documentation

- `docs/REQUIREMENTS.md` — interface/register/protocol freeze.
- `docs/SAFETY.md` — permitted faults and hard "never do" boundary.
- `docs/ARCHITECTURE_DIAGRAM.md` — block diagram matching the RTL.
- `docs/CHARACTERIZATION.md` — measured/derived performance with methodology.

## Status

Simulation-first: all RTL verified in Icarus Verilog. FPGA utilization and
post-route timing are intentionally listed as not-yet-measured in the
characterization doc rather than estimated; they become available after a
synthesis run on the target board.

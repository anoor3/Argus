# ARGUS Build Planner

## Mission
Build ARGUS as a measured, verified hardware system - not as a collection of demo modules.

## Definition of done

- [ ] All RTL builds with no unexplained critical warnings.
- [ ] All automated regression tests pass from a clean checkout.
- [ ] Post-route timing meets the chosen clock target with positive slack.
- [ ] README architecture diagram matches the implemented hierarchy.
- [ ] Measured results include test method, configuration, and raw/log output.
- [ ] A 2-3 minute demo can be repeated without manually editing source code.
- [ ] Every resume claim points to visible evidence in repository/results.
- [ ] At least one real DUT/interface is exercised and monitored.
- [ ] At least one safe fault is injected and recovery is measured.
- [ ] Trace overflow/trigger/simultaneous-event behavior is tested.

# Phase plan

## P0 - Requirements and safety boundary

Freeze the first DUT, FPGA board, I/O voltages, available clocks, and exactly which faults are permitted. Define what ARGUS will never do: no direct over-voltage injection, no raw analog connection to FPGA pins, no glitching clocks with combinational logic.

**Exit:** A written interface/requirements table exists and no unresolved assumption is hidden in RTL.

## P1 - FPGA foundation

Bring up clock/reset, UART host link, CSR bank, LED heartbeat, timestamp counter, and a Python register-access utility. This is the minimum control plane.

**Exit:** A self-checking regression passes and the minimal function is demonstrated on the FPGA.

## P2 - Event capture

Implement GPIO/reset monitors, event normalization, BRAM trace buffer, readout commands, and timestamp correlation. Demonstrate deterministic edge capture.

**Exit:** The new datapath/measurement feature is integrated and produces repeatable expected results.

## P3 - Protocol exercisers

Add I2C and SPI masters plus protocol result logging. Validate against known peripherals or a microcontroller-based DUT.

**Exit:** Edge/error cases are in regression, not only the happy path.

## P4 - Test sequencer

Create a step-based hardware sequencer supporting WRITE, READ_EXPECT, WAIT_EVENT, DELAY, INJECT, CLEAR, and END primitives.

**Exit:** The architectural behavior is demonstrated end-to-end with logs/traces.

## P5 - Fault injection

Add safe digital injection paths with arming, duration limits, and automatic restore. Verify every injection path in simulation before connecting hardware.

**Exit:** Safety/error handling is proven in simulation and on hardware where applicable.

## P6 - Sensors and board bring-up

Add external power/current/temperature monitoring through a sensor IC; build or use a small DUT board with accessible test points and current-safe interfaces.

**Exit:** Telemetry/physical integration is measured and documented.

## P7 - Automation and reporting

Python test-plan loader, JSON/CSV trace export, pass/fail summaries, plots, latency statistics, and regression runs.

**Exit:** One-command automation produces reproducible test results.

## P8 - Characterization

Measure timestamp resolution, event capture limits, UART throughput, protocol clock accuracy, trace depth, resource use, max frequency, and recovery latency under injected faults.

**Exit:** Performance/reliability results include methodology, raw data, and conclusions.

# Measurement plan

- [ ] Timestamp resolution and rollover behavior
- [ ] Maximum sustainable event rate before trace loss
- [ ] BRAM trace depth and record width
- [ ] UART/USB control-plane throughput
- [ ] I2C/SPI configured vs measured clock rate
- [ ] Event-to-trigger latency
- [ ] Fault assertion width accuracy
- [ ] DUT recovery latency after each fault
- [ ] FPGA LUT/FF/BRAM utilization
- [ ] Post-route maximum clock frequency and timing slack

# Evidence to preserve
- Failing regression vector before each meaningful bug fix
- Passing regression log after fix
- Synthesis utilization report
- Post-route timing report
- Hardware demo log/trace
- Raw experiment outputs and analysis script
- Architecture diagram that matches the RTL

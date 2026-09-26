# ARGUS Safety Boundary (P0)

ARGUS can perturb a device under test. This document defines what it is
**permitted** to do and what it must **never** do. `safety_interlock.sv`
enforces these rules in hardware; this doc is the human-readable contract.

## Faults ARGUS is PERMITTED to inject (digital, bounded)

1. **Reset pulse injection** — drive a DUT reset line for a bounded number of
   cycles, then auto-restore.
2. **Bus-response suppression** — mask ACK/response on a protocol master for a
   bounded window to emulate an unresponsive peripheral.
3. **Controlled data corruption** — flip specified bits in a scripted data
   payload (never in random live traffic).
4. **Safe clock-enable manipulation** — gate a *clock-enable* signal, never the
   physical clock net, and never with combinational glitches.

Every injection requires:
- An explicit **arm** step (two-step arm+fire, never single-write).
- A **duration limit** (max cycles); the fault auto-restores at expiry.
- A defined **benign restore state** the output returns to.

## ARGUS will NEVER do

- No direct **over-voltage** or out-of-range voltage injection.
- No **raw analog** connection to FPGA pins (sensors read via I2C/SPI IC only).
- No **combinational clock glitching** or gating of a physical clock net.
- No injection while **un-armed**, or beyond the programmed duration.
- No simultaneous contradictory injections on the same net.

## Enforcement

- `safety_interlock` blocks any fire request that is not armed, exceeds the
  duration limit, or conflicts with an active injection.
- On reset or on any interlock trip, all fault outputs return to benign.
- Every fault path is proven in simulation (assertion + self-checking TB)
  before any hardware connection.

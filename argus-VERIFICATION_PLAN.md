# ARGUS Verification Plan

## Verification philosophy
A waveform is debugging evidence, not the pass/fail mechanism. Tests must be self-checking and reproducible.

## Required layers
- Unit tests for each stateful/protocol/datapath block
- Integration test with a reference model/scoreboard
- Assertions for protocol invariants
- Randomized or exhaustive fault/edge cases where appropriate
- FPGA hardware test with logged inputs/configuration/results

## Completion rule
No feature is complete until its failure modes are exercised, not just its happy path.

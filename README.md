```
   █████╗  ██████╗  ██████╗ ██╗   ██╗███████╗
  ██╔══██╗ ██╔══██╗██╔════╝ ██║   ██║██╔════╝
  ███████║ ██████╔╝██║  ███╗██║   ██║███████╗
  ██╔══██║ ██╔══██╗██║   ██║██║   ██║╚════██║
  ██║  ██║ ██║  ██║╚██████╔╝╚██████╔╝███████║
  ╚═╝  ╚═╝ ╚═╝  ╚═╝ ╚═════╝  ╚═════╝ ╚══════╝
```

# ARGUS — FPGA Hardware Validation & Fault-Injection Instrument

> A programmable piece of test equipment, built inside an FPGA, that **watches**,
> **pokes**, and **safely breaks** other electronic boards to prove they work.

![status](https://img.shields.io/badge/status-simulation--verified-brightgreen)
![rtl](https://img.shields.io/badge/RTL-SystemVerilog-blue)
![tests](https://img.shields.io/badge/RTL%20testbenches-36%20passing-brightgreen)
![host](https://img.shields.io/badge/host%20tests-32%20passing-brightgreen)
![deps](https://img.shields.io/badge/python%20deps-none%20(stdlib)-informational)
![license](https://img.shields.io/badge/build-one%20command-success)

---

## What is this, in plain English?

When engineers build a new circuit board, they have to test it by hand: poke it
with wires, watch signals on a scope, and hope they can repeat what they saw.
It's slow, messy, and different every time.

**ARGUS turns an FPGA into a robot that does this testing for you.** Think of it
as a mix of three lab tools fused into one chip:

| Real lab tool        | What it does          | ARGUS part that does it        |
|----------------------|-----------------------|--------------------------------|
| 🔍 Logic analyzer     | Records what signals do, with exact timing | Monitors + trace buffer |
| 🎛️ Signal generator   | Sends test signals to the board | SPI / I²C / UART masters |
| ⚡ Fault box          | Breaks the board on purpose to test recovery | Fault controller + safety lock |

Everything it sees and does is stamped with **one shared clock**, so every event
lines up on a single timeline you can trust. And it's all driven from a laptop
over a simple serial cable.

---

## Why it's built the way it is

- **Deterministic, not "it worked on my desk."** Tests run the exact same way
  every time, in hardware, with no human timing jitter.
- **Safe by design.** ARGUS can *break* a board on purpose (to test how it
  recovers), but a **hardware safety lock** makes that impossible unless you
  explicitly arm it, cap how long it lasts, and it auto-heals afterward. A
  software bug alone can never damage the device under test.
- **Proven, not promised.** Every hardware block ships with its own
  self-checking test. One command runs **all 36 hardware tests + 32 software
  tests** and gives a single PASS/FAIL.

---

## What it can do

- **👁 Observe** — GPIO, reset, and clock monitors emit timestamped events onto a
  shared 64-bit timeline, saved in a circular trace buffer that flags overflow
  instead of silently losing data.
- **🎚 Stimulate** — SPI, I²C, and UART masters plus an ADC/sensor bridge send
  scripted transactions to the device under test.
- **🧩 Sequence** — a tiny in-hardware "program" runs deterministic test steps
  (`WRITE`, `READ_EXPECT`, `WAIT_EVENT`, `DELAY`, `INJECT`, `CLEAR`, `END`).
- **⚡ Perturb (safely)** — a fault controller applies *bounded* digital faults
  (reset pulse, bus stall, data corruption, clock gating), gated by a two-step
  arm/fire safety interlock with a hard duration cap and automatic restore.
- **🎯 Trigger** — freezes the trace the instant a chosen event happens, keeping
  a configurable window of what came after.
- **🤖 Automate** — a dependency-free Python tool runs JSON test plans, decodes
  traces, and exports JSON/CSV reports with pass/fail summaries.

---

## How it fits together

```
                          YOUR LAPTOP
                              │  (USB / serial cable)
                              ▼
 ┌──────────────────────── ARGUS (on the FPGA) ─────────────────────────┐
 │                                                                       │
 │  UART ▶ command router ◀▶ registers ◀▶ UART       ⏱ 64-bit timebase   │
 │              │                  ▲                    (shared clock)   │
 │              ▼                  │                                     │
 │        test sequencer ─────────┘                                     │
 │              │ inject                                                 │
 │              ▼                                                        │
 │        safety lock ──▶ fault box ──▶  DEVICE UNDER TEST (your board)  │
 │                                                                       │
 │   ┌──────────────── event capture ───────────────┐                   │
 │   │  gpio ┐                                        │                  │
 │   │  reset├─▶ event logger ─▶ trace buffer ─▶ read │                  │
 │   │  clock┘        ▲          (ring, overflow)     │                  │
 │   │           trigger engine (freeze on match)     │                  │
 │   └────────────────────────────────────────────────┘                 │
 └───────────────────────────────────────────────────────────────────────┘
```

*(Full block-by-block diagram: [`docs/ARCHITECTURE_DIAGRAM.md`](docs/ARCHITECTURE_DIAGRAM.md).)*

---

## Try it in 30 seconds

You need `iverilog` (a free Verilog simulator) and `python3`.

```bash
# 1. Run EVERYTHING — all hardware tests + all software tests, one verdict
./scripts/regression.sh

# 2. Run one hardware block's test on its own
make timebase

# 3. Drive a fake instrument from the laptop tool (no hardware needed)
cd host && python3 -m argus.cli run --plan plans/smoke.json --mock
```

---

## What's inside

```
rtl/       the hardware (SystemVerilog) — one small, focused module per file
tb/        a self-checking test for every hardware module
host/       the laptop-side Python tool (talk to it, run plans, make reports)
docs/       requirements, safety rules, architecture diagram, measurements
scripts/    the one-command regression runner
results/    saved proof that the tests pass (regression log + measurements)
```

---

## Proof it works

- **36 hardware testbenches** — each prints `TEST PASSED` / `TEST FAILED` and
  has a built-in watchdog so a broken test fails fast instead of hanging.
- **32 host software tests** — `cd host && python3 -m unittest discover -s tests`.
- **One command checks all of it:** `./scripts/regression.sh` →
  `REGRESSION RESULT: PASS` (saved in [`results/regression_log.txt`](results/regression_log.txt)).

Key measured/derived numbers live in
[`results/MEASUREMENTS.md`](results/MEASUREMENTS.md) — e.g. 20 ns timestamp
resolution, 96-bit trace records, cycle-accurate fault width, 1-cycle
event-to-trigger latency.

---

## Documentation

| Doc | What it covers |
|-----|----------------|
| [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) | Frozen interfaces, register map, command protocol |
| [`docs/SAFETY.md`](docs/SAFETY.md) | Exactly which faults are allowed, and the hard "never do" list |
| [`docs/ARCHITECTURE_DIAGRAM.md`](docs/ARCHITECTURE_DIAGRAM.md) | Block diagram matching the real RTL |
| [`docs/CHARACTERIZATION.md`](docs/CHARACTERIZATION.md) | Performance numbers with methodology |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | How to build, test, and contribute |

---

## Honest status

ARGUS is **simulation-first**: all hardware is verified in the Icarus Verilog
simulator, and the host tooling is fully tested. Figures that need a real chip —
FPGA resource usage and post-route maximum clock speed — are deliberately marked
**"not yet measured"** rather than guessed. They become available after a
synthesis run on a target board. No number in this repo is invented.

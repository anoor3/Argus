# Example test plans

Each file is a JSON test plan consumed by `argus.plan` / `argus.cli`. A plan is
either a bare list of steps or an object with a top-level `"steps"` array.

## Step operations

| op         | fields            | meaning                                    |
|------------|-------------------|--------------------------------------------|
| `check_id` | (none)            | read the ID register, pass if it matches   |
| `write`    | `addr`, `data`    | write a 32-bit value to a register         |
| `read`     | `addr`, `name?`   | read a register (recorded, always passes)  |
| `expect`   | `addr`, `data`    | read and pass only if it equals `data`     |

Values are decimal in JSON (e.g. `3735928559` = `0xDEADBEEF`).

## Files

- `smoke.json` — ID handshake + one scratch write/read + a couple of reads.
- `scratch_sweep.json` — writes/reads several bit patterns through SCRATCH.

## Run

```
cd host
python3 -m argus.cli run --plan plans/smoke.json --mock
python3 -m argus.cli run --plan plans/scratch_sweep.json --mock
```

# ARGUS Host Software

Pure-stdlib Python tools for driving the ARGUS instrument, running test plans,
and turning captured traces into reports. No external dependencies are required
(plotting via matplotlib is optional and guarded).

## Layout

```
host/
  argus/
    protocol.py   command frame encode/decode (matches command_router.sv)
    client.py     RegisterClient over a pluggable transport
    mock.py       in-memory instrument model (mirrors csr_bank semantics)
    trace.py      96-bit trace record decoder
    plan.py       JSON test-plan loader + runner
    report.py     JSON/CSV export + pass/fail summary
    plot.py       optional trace timeline plot (needs matplotlib)
    cli.py        one-command automation entry point
  plans/          example test plans
  tests/          unittest suite (runs without hardware)
```

## Run the tests

```
cd host
python3 -m unittest discover -s tests
```

## One-command automation

```
cd host
python3 -m argus.cli run --plan plans/smoke.json --mock
```

`--mock` uses the built-in instrument model so the flow is reproducible without
hardware. On a real board, drop `--mock` and pass `--port /dev/ttyUSB0`
(requires `pip install pyserial`). Add `--json out.json` to save the result.

## Protocol

Command frame (see `docs/REQUIREMENTS.md`):

```
[CMD][ADDR][DATA3][DATA2][DATA1][DATA0]   (DATA big-endian)
CMD: 0x01 WRITE_REG, 0x02 READ_REG, 0x03 TRACE_READ, 0x04 RUN_SEQ
```

Trace record (96 bits, from `event_logger.sv`):

```
{ timestamp[63:0], source_id[7:0], code[7:0], value[15:0] }
```

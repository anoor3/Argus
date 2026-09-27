"""ARGUS host CLI: one-command automation.

Examples:
    # Run a test plan against the built-in mock instrument and print a summary:
    python3 -m argus.cli run --plan plans/smoke.json --mock

    # Export the summary as JSON:
    python3 -m argus.cli run --plan plans/smoke.json --mock --json out.json

On real hardware you would pass a serial device instead of --mock; the serial
transport is intentionally not imported unless requested so the tool runs with
no external dependencies.
"""

from __future__ import annotations

import argparse
import sys

from .client import RegisterClient
from .mock import MockTransport
from .plan import load_plan, run_plan
from . import report


def _make_transport(args):
    if args.mock:
        return MockTransport()
    # Real serial transport (optional dependency), only imported on demand.
    try:
        import serial  # type: ignore
    except ImportError:
        print("pyserial not installed; use --mock or `pip install pyserial`",
              file=sys.stderr)
        sys.exit(2)
    return serial.Serial(args.port, args.baud, timeout=1)


def cmd_run(args) -> int:
    steps = load_plan(args.plan)
    client = RegisterClient(_make_transport(args))
    result = run_plan(client, steps)
    print(report.summarize(result))
    if args.json:
        with open(args.json, "w") as f:
            f.write(report.plan_to_json(result))
    return 0 if result.passed else 1


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="argus", description="ARGUS host tool")
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="run a test plan")
    r.add_argument("--plan", required=True, help="path to JSON test plan")
    r.add_argument("--mock", action="store_true", help="use the built-in mock")
    r.add_argument("--port", default="/dev/ttyUSB0", help="serial port")
    r.add_argument("--baud", type=int, default=115200)
    r.add_argument("--json", help="write JSON result to this path")
    r.set_defaults(func=cmd_run)
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

"""Export traces and test-plan results to JSON/CSV, and format summaries."""

from __future__ import annotations

import csv
import io
import json

from .plan import PlanResult
from .trace import TraceRecord


def trace_to_json(records: list[TraceRecord]) -> str:
    return json.dumps([r.as_dict() for r in records], indent=2)


def trace_to_csv(records: list[TraceRecord]) -> str:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["timestamp", "source_id", "source", "code", "event", "value"])
    for r in records:
        w.writerow(
            [r.timestamp, r.source_id, r.source_name, r.code, r.code_name, r.value]
        )
    return buf.getvalue()


def plan_to_json(result: PlanResult) -> str:
    return json.dumps(
        {
            "passed": result.passed,
            "n_pass": result.n_pass,
            "n_fail": result.n_fail,
            "steps": [
                {
                    "index": s.index,
                    "op": s.op,
                    "passed": s.passed,
                    "detail": s.detail,
                    "value": s.value,
                }
                for s in result.steps
            ],
        },
        indent=2,
    )


def summarize(result: PlanResult) -> str:
    lines = ["ARGUS test-plan summary", "=" * 30]
    for s in result.steps:
        mark = "PASS" if s.passed else "FAIL"
        val = f" [0x{s.value:X}]" if s.value is not None else ""
        lines.append(f"  [{mark}] step {s.index} {s.op}{val} {s.detail}")
    lines.append("-" * 30)
    verdict = "PASS" if result.passed else "FAIL"
    lines.append(f"OVERALL: {verdict} ({result.n_pass} pass, {result.n_fail} fail)")
    return "\n".join(lines)

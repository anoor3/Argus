"""Test-plan loader and runner.

A test plan is a JSON document describing a sequence of steps to run against
the instrument. Each step is one of:

    {"op": "write",  "addr": 1, "data": 305419896}
    {"op": "expect", "addr": 1, "data": 305419896}
    {"op": "check_id"}
    {"op": "read",   "addr": 4, "name": "time_lo"}

run_plan executes the steps via a RegisterClient and returns a StepResult list
plus an overall pass/fail. This is the one-command automation entry point.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field

from .client import RegisterClient, MAGIC_ID


@dataclass
class StepResult:
    index: int
    op: str
    passed: bool
    detail: str = ""
    value: int | None = None


@dataclass
class PlanResult:
    steps: list = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(s.passed for s in self.steps)

    @property
    def n_pass(self) -> int:
        return sum(1 for s in self.steps if s.passed)

    @property
    def n_fail(self) -> int:
        return sum(1 for s in self.steps if not s.passed)


def load_plan(path: str) -> list:
    with open(path, "r") as f:
        doc = json.load(f)
    if isinstance(doc, dict):
        return doc.get("steps", [])
    return doc


VALID_OPS = {"write", "read", "expect", "check_id"}


def validate_plan(steps: list) -> list:
    """Return a list of human-readable problems with a plan (empty = valid).

    Checks each step has a known op and the fields that op requires, so a bad
    plan is rejected up front instead of failing mid-run.
    """
    problems = []
    for i, step in enumerate(steps):
        op = step.get("op")
        if op not in VALID_OPS:
            problems.append(f"step {i}: unknown op {op!r}")
            continue
        if op in ("write", "read", "expect") and "addr" not in step:
            problems.append(f"step {i}: {op} requires 'addr'")
        if op in ("write", "expect") and "data" not in step:
            problems.append(f"step {i}: {op} requires 'data'")
    return problems


def run_plan(client: RegisterClient, steps: list) -> PlanResult:
    result = PlanResult()
    for i, step in enumerate(steps):
        op = step.get("op")
        try:
            if op == "write":
                client.write_reg(step["addr"], step["data"])
                result.steps.append(StepResult(i, op, True, "wrote"))
            elif op == "read":
                v = client.read_reg(step["addr"])
                result.steps.append(
                    StepResult(i, op, True, step.get("name", ""), value=v)
                )
            elif op == "expect":
                v = client.read_reg(step["addr"])
                ok = v == step["data"]
                result.steps.append(
                    StepResult(
                        i, op, ok,
                        f"exp=0x{step['data']:X} got=0x{v:X}", value=v,
                    )
                )
            elif op == "check_id":
                v = client.read_id()
                ok = v == MAGIC_ID
                result.steps.append(
                    StepResult(i, op, ok, f"id=0x{v:X}", value=v)
                )
            else:
                result.steps.append(StepResult(i, op or "?", False, "unknown op"))
        except Exception as exc:  # noqa: BLE001
            result.steps.append(StepResult(i, op or "?", False, f"error: {exc}"))
    return result

"""Tests for plan validation and shipped example plans."""

import glob
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from argus.client import RegisterClient  # noqa: E402
from argus.mock import MockTransport  # noqa: E402
from argus.plan import load_plan, run_plan, validate_plan  # noqa: E402

PLAN_DIR = os.path.join(os.path.dirname(__file__), "..", "plans")


class TestValidate(unittest.TestCase):
    def test_valid_plan_has_no_problems(self):
        steps = [
            {"op": "check_id"},
            {"op": "write", "addr": 1, "data": 5},
            {"op": "expect", "addr": 1, "data": 5},
        ]
        self.assertEqual(validate_plan(steps), [])

    def test_unknown_op_flagged(self):
        problems = validate_plan([{"op": "nope"}])
        self.assertEqual(len(problems), 1)
        self.assertIn("unknown op", problems[0])

    def test_missing_fields_flagged(self):
        problems = validate_plan([{"op": "write", "addr": 1}])  # no data
        self.assertTrue(any("requires 'data'" in p for p in problems))
        problems = validate_plan([{"op": "expect", "data": 1}])  # no addr
        self.assertTrue(any("requires 'addr'" in p for p in problems))


class TestShippedPlans(unittest.TestCase):
    def test_all_example_plans_are_valid_and_pass(self):
        plans = glob.glob(os.path.join(PLAN_DIR, "*.json"))
        self.assertTrue(plans, "expected example plans to exist")
        for path in plans:
            steps = load_plan(path)
            self.assertEqual(validate_plan(steps), [], f"{path} should validate")
            res = run_plan(RegisterClient(MockTransport()), steps)
            self.assertTrue(res.passed, f"{path} should pass against the mock")


if __name__ == "__main__":
    unittest.main()

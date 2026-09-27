"""Tests for the test-plan runner and report exporters."""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from argus.client import RegisterClient  # noqa: E402
from argus.mock import MockTransport  # noqa: E402
from argus.plan import run_plan  # noqa: E402
from argus import report  # noqa: E402
from argus.trace import decode_stream  # noqa: E402


class TestPlan(unittest.TestCase):
    def test_passing_plan(self):
        c = RegisterClient(MockTransport())
        steps = [
            {"op": "check_id"},
            {"op": "write", "addr": 1, "data": 0x12345678},
            {"op": "expect", "addr": 1, "data": 0x12345678},
        ]
        res = run_plan(c, steps)
        self.assertTrue(res.passed)
        self.assertEqual(res.n_pass, 3)
        self.assertEqual(res.n_fail, 0)

    def test_failing_expect(self):
        c = RegisterClient(MockTransport())
        steps = [
            {"op": "write", "addr": 1, "data": 1},
            {"op": "expect", "addr": 1, "data": 2},  # wrong
        ]
        res = run_plan(c, steps)
        self.assertFalse(res.passed)
        self.assertEqual(res.n_fail, 1)

    def test_unknown_op_fails(self):
        c = RegisterClient(MockTransport())
        res = run_plan(c, [{"op": "frobnicate"}])
        self.assertFalse(res.passed)


class TestReport(unittest.TestCase):
    def _records(self):
        raw = (
            (1).to_bytes(8, "big") + bytes([0x01, 0x01]) + (5).to_bytes(2, "big")
            + (2).to_bytes(8, "big") + bytes([0x03, 0x21]) + (9).to_bytes(2, "big")
        )
        return decode_stream(raw)

    def test_trace_json_roundtrip(self):
        recs = self._records()
        doc = json.loads(report.trace_to_json(recs))
        self.assertEqual(len(doc), 2)
        self.assertEqual(doc[0]["source"], "GPIO")
        self.assertEqual(doc[1]["event"], "CLK_OK")

    def test_trace_csv_header_and_rows(self):
        recs = self._records()
        csv_text = report.trace_to_csv(recs)
        lines = csv_text.strip().splitlines()
        self.assertEqual(lines[0], "timestamp,source_id,source,code,event,value")
        self.assertEqual(len(lines), 3)  # header + 2 rows

    def test_summary_contains_verdict(self):
        c = RegisterClient(MockTransport())
        res = run_plan(c, [{"op": "check_id"}])
        text = report.summarize(res)
        self.assertIn("OVERALL: PASS", text)


if __name__ == "__main__":
    unittest.main()

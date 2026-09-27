"""Test the CLI end-to-end against the mock instrument."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from argus import cli  # noqa: E402

PLAN_DIR = os.path.join(os.path.dirname(__file__), "..", "plans")


class TestCli(unittest.TestCase):
    def test_run_smoke_plan_passes(self):
        plan = os.path.join(PLAN_DIR, "smoke.json")
        rc = cli.main(["run", "--plan", plan, "--mock"])
        self.assertEqual(rc, 0)

    def test_run_writes_json(self):
        plan = os.path.join(PLAN_DIR, "smoke.json")
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "result.json")
            rc = cli.main(["run", "--plan", plan, "--mock", "--json", out])
            self.assertEqual(rc, 0)
            self.assertTrue(os.path.exists(out))
            with open(out) as f:
                self.assertIn("\"passed\": true", f.read())


if __name__ == "__main__":
    unittest.main()

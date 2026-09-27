"""Round-trip test: export trace to CSV, re-parse, confirm fidelity."""

import csv
import io
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from argus import report  # noqa: E402
from argus.trace import decode_stream  # noqa: E402


def _pack(ts, src, code, val):
    return ts.to_bytes(8, "big") + bytes([src, code]) + val.to_bytes(2, "big")


class TestCsvRoundTrip(unittest.TestCase):
    def test_csv_reparses_to_same_values(self):
        raw = (
            _pack(100, 0x01, 0x01, 5)
            + _pack(250, 0x02, 0x10, 0)
            + _pack(410, 0x03, 0x21, 12)
        )
        records = decode_stream(raw)
        csv_text = report.trace_to_csv(records)

        reader = csv.DictReader(io.StringIO(csv_text))
        rows = list(reader)
        self.assertEqual(len(rows), 3)
        self.assertEqual(int(rows[0]["timestamp"]), 100)
        self.assertEqual(rows[0]["source"], "GPIO")
        self.assertEqual(int(rows[2]["value"]), 12)
        self.assertEqual(rows[1]["event"], "RST_ASSERT")

    def test_json_reparses(self):
        import json

        records = decode_stream(_pack(7, 0x03, 0x20, 3))
        doc = json.loads(report.trace_to_json(records))
        self.assertEqual(doc[0]["timestamp"], 7)
        self.assertEqual(doc[0]["event"], "CLK_LOST")


if __name__ == "__main__":
    unittest.main()

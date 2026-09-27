"""Tests for argus.stats."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from argus import stats  # noqa: E402
from argus.trace import decode_stream  # noqa: E402


def _pack(ts, src, code, val):
    return ts.to_bytes(8, "big") + bytes([src, code]) + val.to_bytes(2, "big")


class TestStats(unittest.TestCase):
    def _recs(self):
        raw = (
            _pack(100, 0x01, 0x01, 0)
            + _pack(120, 0x01, 0x02, 0)  # +20
            + _pack(170, 0x02, 0x10, 0)  # +50
        )
        return decode_stream(raw)

    def test_intervals(self):
        self.assertEqual(stats.inter_event_intervals(self._recs()), [20, 50])

    def test_interval_stats(self):
        s = stats.interval_stats(self._recs())
        self.assertEqual(s["count"], 3)
        self.assertEqual(s["min"], 20)
        self.assertEqual(s["max"], 50)
        self.assertEqual(s["mean"], 35.0)

    def test_empty_stats(self):
        s = stats.interval_stats([])
        self.assertIsNone(s["min"])

    def test_per_source_counts(self):
        c = stats.per_source_counts(self._recs())
        self.assertEqual(c["GPIO"], 2)
        self.assertEqual(c["RESET"], 1)


if __name__ == "__main__":
    unittest.main()

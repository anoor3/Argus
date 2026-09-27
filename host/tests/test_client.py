"""Tests for RegisterClient against the in-memory MockTransport."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from argus.client import RegisterClient, MAGIC_ID  # noqa: E402
from argus.mock import MockTransport  # noqa: E402


class TestRegisterClient(unittest.TestCase):
    def test_id_readback(self):
        c = RegisterClient(MockTransport())
        self.assertEqual(c.read_id(), MAGIC_ID)
        self.assertTrue(c.check_id())

    def test_scratch_write_read(self):
        c = RegisterClient(MockTransport())
        c.write_reg(0x01, 0xCAFEF00D)
        self.assertEqual(c.read_reg(0x01), 0xCAFEF00D)

    def test_ro_write_ignored(self):
        c = RegisterClient(MockTransport())
        c.write_reg(0x03, 0xFFFFFFFF)  # STATUS is RO
        self.assertEqual(c.read_reg(0x03), 0x00000000)

    def test_time_split(self):
        c = RegisterClient(MockTransport(time_now=0x1122334455667788))
        self.assertEqual(c.read_time(), 0x1122334455667788)

    def test_event_count(self):
        c = RegisterClient(MockTransport(events=42))
        self.assertEqual(c.read_event_count(), 42)

    def test_read_trace(self):
        rec = (
            (0x55).to_bytes(8, "big") + bytes([0x01, 0x01]) + (7).to_bytes(2, "big")
        )
        c = RegisterClient(MockTransport(trace_records=[rec]))
        recs = c.read_trace(1)
        self.assertEqual(len(recs), 1)
        self.assertEqual(recs[0].timestamp, 0x55)
        self.assertEqual(recs[0].source_name, "GPIO")
        self.assertEqual(recs[0].value, 7)


if __name__ == "__main__":
    unittest.main()

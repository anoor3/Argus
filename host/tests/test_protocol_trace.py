"""Unit tests for argus.protocol and argus.trace."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from argus import protocol, trace  # noqa: E402


class TestProtocol(unittest.TestCase):
    def test_encode_write_frame(self):
        f = protocol.encode_write(0x01, 0xDEADBEEF)
        self.assertEqual(f, bytes([0x01, 0x01, 0xDE, 0xAD, 0xBE, 0xEF]))

    def test_encode_read_frame(self):
        f = protocol.encode_read(0x04)
        self.assertEqual(f, bytes([0x02, 0x04, 0x00, 0x00, 0x00, 0x00]))

    def test_decode_response(self):
        self.assertEqual(
            protocol.decode_response(bytes([0x11, 0x22, 0x33, 0x44])),
            0x11223344,
        )

    def test_encode_rejects_out_of_range(self):
        with self.assertRaises(ValueError):
            protocol.encode_frame(0x01, 0x01, 0x1_0000_0000)

    def test_decode_response_length_check(self):
        with self.assertRaises(ValueError):
            protocol.decode_response(bytes([1, 2, 3]))


class TestTrace(unittest.TestCase):
    def _pack(self, ts, src, code, val):
        return (
            ts.to_bytes(8, "big")
            + bytes([src, code])
            + val.to_bytes(2, "big")
        )

    def test_decode_record_fields(self):
        raw = self._pack(0x1122334455667788, 0x02, 0x10, 0xBEEF)
        r = trace.decode_record(raw)
        self.assertEqual(r.timestamp, 0x1122334455667788)
        self.assertEqual(r.source_id, 0x02)
        self.assertEqual(r.source_name, "RESET")
        self.assertEqual(r.code, 0x10)
        self.assertEqual(r.code_name, "RST_ASSERT")
        self.assertEqual(r.value, 0xBEEF)

    def test_decode_stream_multiple(self):
        raw = self._pack(1, 0x01, 0x01, 5) + self._pack(2, 0x03, 0x21, 9)
        recs = trace.decode_stream(raw)
        self.assertEqual(len(recs), 2)
        self.assertEqual(recs[0].timestamp, 1)
        self.assertEqual(recs[1].source_name, "CLOCK")
        self.assertEqual(recs[1].code_name, "CLK_OK")

    def test_stream_length_validation(self):
        with self.assertRaises(ValueError):
            trace.decode_stream(bytes(13))


if __name__ == "__main__":
    unittest.main()

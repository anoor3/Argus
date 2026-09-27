"""Register-access client for the ARGUS instrument.

Provides read_reg / write_reg / read_trace over a pluggable transport. The
transport is any object with write(bytes) and read(n)->bytes methods (e.g. a
pyserial Serial instance on real hardware, or MockTransport in tests), so the
client logic is verifiable without a device attached.
"""

from __future__ import annotations

from . import protocol
from .trace import RECORD_BYTES, decode_stream

# Known register addresses (match docs/REQUIREMENTS.md)
REG_ID = 0x00
REG_SCRATCH = 0x01
REG_CTRL = 0x02
REG_STATUS = 0x03
REG_TIME_LO = 0x04
REG_TIME_HI = 0x05
REG_EVENT_COUNT = 0x06
REG_TRACE_RDATA = 0x07

MAGIC_ID = 0xA2600101


class RegisterClient:
    def __init__(self, transport):
        self.t = transport

    def write_reg(self, addr: int, data: int) -> None:
        self.t.write(protocol.encode_write(addr, data))

    def read_reg(self, addr: int) -> int:
        self.t.write(protocol.encode_read(addr))
        resp = self.t.read(4)
        return protocol.decode_response(resp)

    def read_id(self) -> int:
        return self.read_reg(REG_ID)

    def check_id(self) -> bool:
        return self.read_id() == MAGIC_ID

    def read_time(self) -> int:
        """Read the 64-bit timebase as hi<<32 | lo."""
        lo = self.read_reg(REG_TIME_LO)
        hi = self.read_reg(REG_TIME_HI)
        return (hi << 32) | lo

    def read_event_count(self) -> int:
        return self.read_reg(REG_EVENT_COUNT)

    def read_trace(self, n_records: int) -> list:
        """Pop n_records trace records via TRACE_READ frames."""
        raw = bytearray()
        for _ in range(n_records):
            self.t.write(protocol.encode_frame(protocol.CMD_TRACE, REG_TRACE_RDATA, 0))
            raw.extend(self.t.read(RECORD_BYTES))
        return decode_stream(bytes(raw))

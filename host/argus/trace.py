"""Decode ARGUS trace records.

Each record is 96 bits, packed by rtl/event_logger.sv as:

    { timestamp[63:0], source_id[7:0], code[7:0], value[15:0] }

which is 12 bytes big-endian on the wire.
"""

from __future__ import annotations

from dataclasses import dataclass

RECORD_BYTES = 12

# Source ids (match rtl/argus_events.svh)
SOURCES = {0x01: "GPIO", 0x02: "RESET", 0x03: "CLOCK"}

# Event codes (match rtl/argus_events.svh)
CODES = {
    0x01: "RISE",
    0x02: "FALL",
    0x10: "RST_ASSERT",
    0x11: "RST_DEASSERT",
    0x20: "CLK_LOST",
    0x21: "CLK_OK",
}


@dataclass
class TraceRecord:
    timestamp: int
    source_id: int
    code: int
    value: int

    @property
    def source_name(self) -> str:
        return SOURCES.get(self.source_id, f"0x{self.source_id:02X}")

    @property
    def code_name(self) -> str:
        return CODES.get(self.code, f"0x{self.code:02X}")

    def as_dict(self) -> dict:
        return {
            "timestamp": self.timestamp,
            "source_id": self.source_id,
            "source": self.source_name,
            "code": self.code,
            "event": self.code_name,
            "value": self.value,
        }


def decode_record(raw: bytes) -> TraceRecord:
    """Decode 12 big-endian bytes into a TraceRecord."""
    if len(raw) != RECORD_BYTES:
        raise ValueError(f"expected {RECORD_BYTES} bytes, got {len(raw)}")
    ts = int.from_bytes(raw[0:8], "big")
    src = raw[8]
    code = raw[9]
    val = int.from_bytes(raw[10:12], "big")
    return TraceRecord(timestamp=ts, source_id=src, code=code, value=val)


def decode_stream(raw: bytes) -> list[TraceRecord]:
    """Decode a concatenation of records."""
    if len(raw) % RECORD_BYTES != 0:
        raise ValueError("stream length is not a multiple of record size")
    return [
        decode_record(raw[i : i + RECORD_BYTES])
        for i in range(0, len(raw), RECORD_BYTES)
    ]

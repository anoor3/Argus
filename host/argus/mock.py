"""In-memory mock of the ARGUS instrument for host-side tests.

Implements the same command frame protocol as rtl/command_router.sv +
rtl/csr_bank.sv, so the host client can be tested end-to-end without hardware.
This is a *model*, not the RTL; the RTL is verified separately in simulation.
"""

from __future__ import annotations

from . import protocol
from .client import (
    MAGIC_ID,
    REG_CTRL,
    REG_EVENT_COUNT,
    REG_ID,
    REG_SCRATCH,
    REG_STATUS,
    REG_TIME_HI,
    REG_TIME_LO,
)


class MockTransport:
    def __init__(self, time_now: int = 0, events: int = 0, trace_records=None):
        self.scratch = 0
        self.ctrl = 0
        self.status = 0
        self.time_now = time_now & 0xFFFFFFFFFFFFFFFF
        self.event_count = events
        self._trace = list(trace_records or [])  # list of 12-byte records
        self._out = bytearray()  # bytes queued for the host to read

    # ---- transport interface ----
    def write(self, frame: bytes) -> None:
        assert len(frame) == protocol.FRAME_LEN
        cmd, addr = frame[0], frame[1]
        data = int.from_bytes(frame[2:6], "big")
        if cmd == protocol.CMD_WRITE:
            self._do_write(addr, data)
        elif cmd == protocol.CMD_READ:
            self._out.extend(self._do_read(addr).to_bytes(4, "big"))
        elif cmd == protocol.CMD_TRACE:
            rec = self._trace.pop(0) if self._trace else bytes(12)
            self._out.extend(rec)
        # RUNSEQ: no response modeled

    def read(self, n: int) -> bytes:
        out, self._out = bytes(self._out[:n]), self._out[n:]
        return out

    # ---- register model ----
    def _do_write(self, addr, data):
        if addr == REG_SCRATCH:
            self.scratch = data
        elif addr == REG_CTRL:
            self.ctrl = data
        # RO writes ignored (matches csr_bank)

    def _do_read(self, addr) -> int:
        return {
            REG_ID: MAGIC_ID,
            REG_SCRATCH: self.scratch,
            REG_CTRL: self.ctrl,
            REG_STATUS: self.status,
            REG_TIME_LO: self.time_now & 0xFFFFFFFF,
            REG_TIME_HI: (self.time_now >> 32) & 0xFFFFFFFF,
            REG_EVENT_COUNT: self.event_count,
        }.get(addr, 0)

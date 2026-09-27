"""ARGUS host<->instrument command protocol.

Mirrors the frame defined in docs/REQUIREMENTS.md and implemented by
rtl/command_router.sv:

    [CMD][ADDR][DATA3][DATA2][DATA1][DATA0]   (DATA big-endian, MSB first)

Read responses return 4 data bytes, big-endian.
"""

from __future__ import annotations

# Command opcodes (must match rtl/command_router.sv)
CMD_WRITE = 0x01
CMD_READ = 0x02
CMD_TRACE = 0x03
CMD_RUNSEQ = 0x04

FRAME_LEN = 6


def encode_frame(cmd: int, addr: int, data: int = 0) -> bytes:
    """Encode a 6-byte command frame.

    data is a 32-bit value sent big-endian (MSB first).
    """
    if not 0 <= cmd <= 0xFF:
        raise ValueError(f"cmd out of range: {cmd}")
    if not 0 <= addr <= 0xFF:
        raise ValueError(f"addr out of range: {addr}")
    if not 0 <= data <= 0xFFFFFFFF:
        raise ValueError(f"data out of range: {data}")
    return bytes(
        [
            cmd & 0xFF,
            addr & 0xFF,
            (data >> 24) & 0xFF,
            (data >> 16) & 0xFF,
            (data >> 8) & 0xFF,
            data & 0xFF,
        ]
    )


def encode_write(addr: int, data: int) -> bytes:
    return encode_frame(CMD_WRITE, addr, data)


def encode_read(addr: int) -> bytes:
    return encode_frame(CMD_READ, addr, 0)


def decode_response(resp: bytes) -> int:
    """Decode a 4-byte big-endian read response into a 32-bit int."""
    if len(resp) != 4:
        raise ValueError(f"expected 4 response bytes, got {len(resp)}")
    return (resp[0] << 24) | (resp[1] << 16) | (resp[2] << 8) | resp[3]

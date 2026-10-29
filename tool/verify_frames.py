#!/usr/bin/env python3
"""Reference frame builder + checks (stdlib only). Mirrors lib/whoop_protocol.dart.
Run:  python3 tool/verify_frames.py
Checks the builder against the one public hardware-proven vector (CLIENT_HELLO)
and prints the haptic frames the app will send. The haptic frames themselves are
NOT hardware-verified by this script."""
import zlib, struct, sys

def crc16_modbus(data: bytes) -> int:
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc & 0xFFFF

def build(seq: int, cmd: int, body: bytes = b"") -> bytes:
    inner = bytes([0x23, seq & 0xFF, cmd & 0xFF]) + body
    inner += b"\x00" * (-len(inner) % 4)
    length = len(inner) + 4                      # frame length - 8
    header = bytes([0xAA, 0x01]) + struct.pack("<H", length) + bytes([0x00, 0x01])
    return header + struct.pack("<H", crc16_modbus(header)) + inner + struct.pack("<I", zlib.crc32(inner))

def haptic_body(pulses: int) -> bytes:
    loops = max(1, min(8, pulses))
    return bytes([0x01, 0x2F, 0x98]) + bytes(8) + bytes([loops - 1])

HELLO_VECTOR = bytes.fromhex("AA0108000001E67123019101363E5C8D")

if __name__ == "__main__":
    hello = build(1, 0x91, b"\x01")
    print("CLIENT_HELLO built :", hello.hex().upper())
    print("CLIENT_HELLO vector:", HELLO_VECTOR.hex().upper())
    ok = hello == HELLO_VECTOR
    print("MATCH" if ok else "MISMATCH")
    for n in (1, 2, 3, 8):
        print(f"buzz x{n} (seq 2):", build(2, 0x13, haptic_body(n)).hex().upper())
    sys.exit(0 if ok else 1)

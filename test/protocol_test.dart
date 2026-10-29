import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_buzz/whoop_protocol.dart';

void main() {
  test('CLIENT_HELLO matches the published hardware-proven frame', () {
    expect(toHex(buildClientHello(seq: 1)).replaceAll(' ', ''), 'AA0108000001E67123019101363E5C8D');
  });

  test('CRC helpers agree with the published CLIENT_HELLO CRCs', () {
    expect(crc16Modbus([0xAA, 0x01, 0x08, 0x00, 0x00, 0x01]), 0x71E6);
    expect(crc32([0x23, 0x01, 0x91, 0x01]), 0x8D5C3E36);
  });

  test('haptic frames (golden values from tool/verify_frames.py; NOT hardware proof)', () {
    final g = {
      1: 'AA0114000001E1E1230213012F9800000000000000000000E1A1FEB4',
      2: 'AA0114000001E1E1230213012F9800000000000000000100A090E5AD',
      3: 'AA0114000001E1E1230213012F980000000000000000020063C3C886',
    };
    g.forEach((n, hex) {
      expect(toHex(buildHapticFrame(seq: 2, pulses: n)).replaceAll(' ', ''), hex);
    });
  });

  test('pulse count is capped at 3 (loop byte 0..2) so a buzz can never be long', () {
    expect(hapticBody(0).last, 0);
    expect(hapticBody(99).last, 2);
  });

  test('stop frame (golden from tool/verify_frames.py; opcode UNVERIFIED on 5.0)', () {
    expect(toHex(buildStopHapticsFrame(seq: 2)).replaceAll(' ', ''), 'AA0108000001E67123027A00DE9A9745');
  });

  test('reassembler joins fragments', () {
    final f = buildHapticFrame(seq: 5, pulses: 2);
    final r = FrameReassembler();
    expect(r.feed(f.sublist(0, 10)), isEmpty);
    final out = r.feed(f.sublist(10));
    expect(out.length, 1);
    expect(out.first, f);
  });
}

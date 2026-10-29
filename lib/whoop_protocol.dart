// WHOOP 5.0 / MG ("Maverick") wire protocol - the minimum needed to buzz.
//
// Sources (community reverse engineering, not WHOOP documentation):
//  * LeonardSEO/wearable5.0 FINDINGS.md  - GATT map, envelope, CRCs, padding,
//    CLIENT_HELLO test vector (checked against real 5/MG frames).
//  * Sophonbot0/whoop-vault README        - inner layout, 4-byte alignment.
//  * tanarchytan/noop PR #6 + whoop-rs    - haptic opcode 0x13 and the 12-byte
//    body (loop count in the last byte), reported working on a real 5/MG.
//
// Evidence level of each constant is noted inline. Nothing here is invented.
import 'dart:typed_data';

class WhoopUuids {
  /// MAVERICK (WHOOP 5.0 / MG) service. Source: wearable5.0 FINDINGS s1 (apk).
  static const service = 'fd4b0001-cce1-4033-93ce-002d5875f58a';

  /// Characteristics are published as fd4b0002..0007 on that service.
  /// The sources abbreviate the full 128-bit form, so the app matches them by
  /// their 8-hex-digit prefix instead of assuming the base UUID.
  static const cmdWritePrefix = 'fd4b0002'; // commands -> strap
  static const cmdNotifyPrefix = 'fd4b0003'; // command responses
  static const eventsPrefix = 'fd4b0004'; // events
  static const dataPrefix = 'fd4b0005'; // history / realtime data
  static const memfaultPrefix = 'fd4b0007';
}

class WhoopCmd {
  static const int packetTypeCommand = 0x23; // 35, whoop-vault + CLIENT_HELLO vector
  static const int packetTypeCommandResponse = 36; // wearable5.0 s2
  static const int clientHello = 0x91; // 145, from the CLIENT_HELLO vector
  static const int runHaptic = 0x13; // 19, noop PR #6 (5/MG haptic)
  // STOP_HAPTICS: 122 (0x7A) in community WHOOP 4.0 command lists. UNVERIFIED on
  // a WHOOP 5.0; sent as a best-effort stop. Do not rely on it alone.
  static const int stopHaptics = 0x7A;
}

int crc16Modbus(List<int> data) {
  var crc = 0xFFFF;
  for (final b in data) {
    crc ^= b & 0xFF;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xA001 : crc >> 1;
    }
  }
  return crc & 0xFFFF;
}

final List<int> _crc32Table = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
  }
  return c;
});

/// CRC-32 as used by zlib.crc32.
int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crc32Table[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Format-1 request frame:
/// AA 01 | len u16le (= frame-8) | 00 01 | crc16le(header) | inner | crc32le(inner)
/// inner = [0x23][seq][cmd][body...] zero-padded to a multiple of 4.
Uint8List buildCommandFrame({
  required int seq,
  required int command,
  List<int> body = const [],
}) {
  final inner = <int>[WhoopCmd.packetTypeCommand, seq & 0xFF, command & 0xFF, ...body];
  while (inner.length % 4 != 0) {
    inner.add(0);
  }
  final len = inner.length + 4;
  final header = <int>[0xAA, 0x01, len & 0xFF, (len >> 8) & 0xFF, 0x00, 0x01];
  final h = crc16Modbus(header);
  final c = crc32(inner);
  return Uint8List.fromList([
    ...header,
    h & 0xFF,
    (h >> 8) & 0xFF,
    ...inner,
    c & 0xFF,
    (c >> 8) & 0xFF,
    (c >> 16) & 0xFF,
    (c >> 24) & 0xFF,
  ]);
}

/// Static CLIENT_HELLO: reproduces the published, hardware-proven frame
/// AA0108000001E67123019101363E5C8D when seq == 1.
Uint8List buildClientHello({int seq = 1}) =>
    buildCommandFrame(seq: seq, command: WhoopCmd.clientHello, body: const [0x01]);

/// Haptic body, 12 bytes. Bytes 0..2 (01 2F 98) are copied verbatim from the
/// community-reported working frame; their meaning (waveform / strength /
/// duration) is UNKNOWN. Last byte = overallLoop = pulses-1, clamped 0..7.
const int maxPulsesPerCommand = 3; // safety cap: a buzz can never be long
const int maxExperimentalPulses = 8; // the old "Long" setting; behaviour on 5.0 unknown
List<int> hapticBody(int pulses, {bool experimental = false, int b2 = 0x98}) {
  final loops = pulses.clamp(1, experimental ? maxExperimentalPulses : maxPulsesPerCommand);
  return <int>[0x01, 0x2F, b2 & 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, loops - 1];
}

Uint8List buildHapticFrame({required int seq, required int pulses, bool experimental = false, int b2 = 0x98}) =>
    buildCommandFrame(seq: seq, command: WhoopCmd.runHaptic, body: hapticBody(pulses, experimental: experimental, b2: b2));

/// Best-effort stop frame (opcode unverified on 5.0, see [WhoopCmd.stopHaptics]).
Uint8List buildStopHapticsFrame({required int seq}) =>
    buildCommandFrame(seq: seq, command: WhoopCmd.stopHaptics, body: const [0x00]);

/// Reassembles BLE notification fragments into complete frames.
/// Only the first fragment of a frame begins with AA 01.
class FrameReassembler {
  final List<int> _buf = [];

  List<Uint8List> feed(List<int> chunk) {
    final out = <Uint8List>[];
    if (chunk.length >= 2 && chunk[0] == 0xAA && chunk[1] == 0x01) {
      _buf.clear();
    } else if (_buf.isEmpty) {
      return out; // stray fragment, drop
    }
    _buf.addAll(chunk);
    while (_buf.length >= 4) {
      final expected = (_buf[2] | (_buf[3] << 8)) + 8;
      if (_buf.length < expected) break;
      out.add(Uint8List.fromList(_buf.sublist(0, expected)));
      _buf.removeRange(0, expected);
      if (_buf.length < 2 || _buf[0] != 0xAA) {
        _buf.clear();
        break;
      }
    }
    return out;
  }
}

class ParsedResponse {
  ParsedResponse(this.type, this.seq, this.cmd, this.originSeq, this.result, this.crcOk);
  final int type, seq, cmd, originSeq, result;
  final bool crcOk;

  String get resultName => switch (result) {
        0 => 'failure',
        1 => 'success',
        2 => 'pending',
        3 => 'unsupported',
        _ => 'code $result',
      };
}

/// Parses a command response: inner = [36][seq][cmd][origin seq][result][body...]
/// (wearable5.0 FINDINGS s2). Returns null for anything else.
ParsedResponse? parseResponse(Uint8List f) {
  if (f.length < 17 || f[0] != 0xAA || f[1] != 0x01) return null;
  final headerOk = crc16Modbus(f.sublist(0, 6)) == (f[6] | (f[7] << 8));
  final end = f.length - 4;
  final bodyCrc = f[end] | (f[end + 1] << 8) | (f[end + 2] << 16) | (f[end + 3] << 24);
  final crcOk = headerOk && crc32(f.sublist(8, end)) == bodyCrc;
  if (f[8] != WhoopCmd.packetTypeCommandResponse) return null;
  return ParsedResponse(f[8], f[9], f[10], f[11], f[12], crcOk);
}

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase();

List<int>? fromHex(String s) {
  final clean = s.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (clean.isEmpty || clean.length.isOdd) return null;
  return [for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16)];
}

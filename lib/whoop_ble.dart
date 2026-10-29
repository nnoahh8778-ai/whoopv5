import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'whoop_protocol.dart';

enum LinkState { idle, scanning, connecting, discovering, bonding, handshaking, ready, reconnecting, error }

/// Owns the BLE connection to one WHOOP 5.0 strap.
class WhoopController extends ChangeNotifier {
  static const _prefKey = 'last_device_id';

  LinkState state = LinkState.idle;
  String? error;
  String? hint; // actionable advice shown under the error
  BluetoothDevice? device;
  List<ScanResult> scanResults = [];
  List<BluetoothService> services = [];
  final List<String> log = [];

  bool serviceFound = false;
  bool helloAcked = false;
  int? mtu;
  int? rssi;
  String bondText = 'unknown';
  String? lastResponse; // last strap reply to a haptic command

  BluetoothCharacteristic? _cmdWrite, _cmdNotify;
  StreamSubscription? _scanSub, _connSub, _notifySub0, _notifySub1, _bondSub;
  final FrameReassembler _reasm = FrameReassembler();
  int _seq = 1;
  bool _manualDisconnect = false;
  bool _reconnecting = false;
  Completer<ParsedResponse>? _awaitedHello;
  final Map<int, Completer<ParsedResponse>> _pending = {};
  Future<void> _writeChain = Future.value();

  bool get isReady => state == LinkState.ready;

  // ---------------------------------------------------------------- logging
  void _log(String s) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    log.add('$t  $s');
    if (log.length > 400) log.removeRange(0, log.length - 400);
    debugPrint('[whoop] $s');
    notifyListeners();
  }

  void _set(LinkState s) {
    state = s;
    notifyListeners();
  }

  void _fail(Object e, {String? advice}) {
    error = e.toString();
    hint = advice;
    _log('ERROR: $error');
    _set(LinkState.error);
  }

  // ------------------------------------------------------------ permissions
  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true; // iOS prompts automatically
    final res = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
    final scan = res[Permission.bluetoothScan]?.isGranted ?? false;
    final conn = res[Permission.bluetoothConnect]?.isGranted ?? false;
    final loc = res[Permission.locationWhenInUse]?.isGranted ?? false;
    // Android 12+: scan+connect are enough. Android <=11: location is required
    // (permission_handler reports bluetoothScan as granted there).
    if (!(scan && conn)) {
      _fail('Bluetooth permission denied', advice: 'Grant "Nearby devices" permission in system settings.');
      return false;
    }
    if (!loc) _log('Location permission not granted (fine on Android 12+, required on 11 and below).');
    return true;
  }

  Future<bool> _ensureAdapterOn() async {
    final s = await FlutterBluePlus.adapterState.first;
    if (s == BluetoothAdapterState.on) return true;
    _fail('Bluetooth is off', advice: 'Turn Bluetooth on and try again.');
    return false;
  }

  // ------------------------------------------------------------------- scan
  bool showAllDevices = false;

  bool _looksLikeWhoop(ScanResult r) {
    final n = (r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName).toUpperCase();
    final hasSvc = r.advertisementData.serviceUuids.any((g) => g.str128.toLowerCase() == WhoopUuids.service);
    return n.startsWith('WHOOP') || hasSvc;
  }

  Future<void> startScan({bool all = false}) async {
    showAllDevices = all;
    if (!await _ensurePermissions() || !await _ensureAdapterOn()) return;
    error = null;
    hint = null;
    scanResults = [];
    _set(LinkState.scanning);
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      scanResults = (all ? list : list.where(_looksLikeWhoop).toList())..sort((a, b) => b.rssi.compareTo(a.rssi));
      notifyListeners();
    });
    _log('Scanning ${all ? "(all devices)" : "(WHOOP only)"} ...');
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 12));
      await FlutterBluePlus.isScanning.where((s) => s == false).first;
    } catch (e) {
      _fail(e);
      return;
    }
    if (state == LinkState.scanning) {
      _set(LinkState.idle);
      if (scanResults.isEmpty) {
        hint = 'No WHOOP found. Put the strap in pairing mode (tap it repeatedly until the LED flashes blue), '
            'fully quit the official WHOOP app, and turn off Bluetooth on any other phone it is bonded to.';
        notifyListeners();
      }
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (state == LinkState.scanning) _set(LinkState.idle);
  }

  // ---------------------------------------------------------------- connect
  Future<void> connect(BluetoothDevice d) async {
    _manualDisconnect = false;
    await FlutterBluePlus.stopScan();
    device = d;
    error = null;
    hint = null;
    helloAcked = false;
    serviceFound = false;
    _set(LinkState.connecting);
    _log('Connecting to ${d.remoteId.str} ...');
    try {
      await _connSub?.cancel();
      _connSub = d.connectionState.listen(_onConnectionState);
      await d.connect(timeout: const Duration(seconds: 20), autoConnect: false);
      if (Platform.isAndroid) {
        try {
          mtu = await d.requestMtu(247);
        } catch (_) {}
      } else {
        mtu = d.mtuNow;
      }
      _set(LinkState.discovering);
      services = await d.discoverServices();
      _bindCharacteristics();
      if (!serviceFound) {
        _fail('WHOOP 5.0 service (fd4b0001...) not found',
            advice: 'This looks like a different device or a WHOOP 4.0. Check the Diagnostics tab for the service list.');
        await d.disconnect();
        return;
      }
      await _subscribe();
      await _bondIfNeeded(d);
      await _handshake();
      final p = await SharedPreferences.getInstance();
      await p.setString(_prefKey, d.remoteId.str);
    } catch (e) {
      _fail(e, advice: _adviceFor(e));
    }
  }

  String? _adviceFor(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('insufficient') || s.contains('bond') || s.contains('pair') || s.contains('auth')) {
      return 'The strap holds ONE encrypted bond. Quit the official WHOOP app, turn Bluetooth off on the phone '
          'it is bonded to, remove the strap from this phone\'s Bluetooth settings, tap the strap into pairing mode '
          '(blue LED) and retry.';
    }
    if (s.contains('timeout')) return 'Move closer, make sure the strap is charged, and that no other app is connected to it.';
    return null;
  }

  void _bindCharacteristics() {
    _cmdWrite = _cmdNotify = null;
    for (final s in services) {
      if (s.uuid.str128.toLowerCase() != WhoopUuids.service) continue;
      serviceFound = true;
      for (final c in s.characteristics) {
        final u = c.uuid.str128.toLowerCase();
        if (u.startsWith(WhoopUuids.cmdWritePrefix)) _cmdWrite = c;
        if (u.startsWith(WhoopUuids.cmdNotifyPrefix)) _cmdNotify = c;
      }
    }
    _log('Service found: $serviceFound, cmd-write: ${_cmdWrite?.uuid.str128}, cmd-notify: ${_cmdNotify?.uuid.str128}');
    if (_cmdWrite == null || _cmdNotify == null) serviceFound = false;
  }

  Future<void> _subscribe() async {
    await _notifySub0?.cancel();
    await _notifySub1?.cancel();
    // Only the command-response channel is needed for buzzing. Not subscribing
    // to history/data characteristics keeps radio traffic and battery use low.
    _notifySub0 = _cmdNotify!.onValueReceived.listen(_onNotify);
    device!.cancelWhenDisconnected(_notifySub0!);
    await _cmdNotify!.setNotifyValue(true);
    _log('Subscribed to command responses');
  }

  Future<void> _bondIfNeeded(BluetoothDevice d) async {
    if (Platform.isAndroid) {
      final bs = await d.bondState.first;
      bondText = bs.name;
      if (bs != BluetoothBondState.bonded) {
        _set(LinkState.bonding);
        _log('Requesting bond (Android pairing dialog) ...');
        await d.createBond(timeout: 45);
        bondText = (await d.bondState.first).name;
      }
    } else {
      bondText = 'managed by iOS';
    }
    notifyListeners();
  }

  Future<void> _handshake() async {
    _set(LinkState.handshaking);
    final seq = _nextSeq();
    final frame = buildClientHello(seq: seq);
    _awaitedHello = Completer<ParsedResponse>();
    await _writeRaw(frame, label: 'CLIENT_HELLO');
    try {
      final r = await _awaitedHello!.future.timeout(const Duration(seconds: 6));
      helloAcked = r.result == 1 || r.result == 2;
      _log('CLIENT_HELLO reply: ${r.resultName} (crc ${r.crcOk ? "ok" : "BAD"})');
    } on TimeoutException {
      helloAcked = false;
      _log('No CLIENT_HELLO reply within 6 s - link not confirmed.');
    }
    _reconnectAttempt = 0;
    _set(LinkState.ready);
  }

  // ------------------------------------------------------------ disconnects
  int _reconnectAttempt = 0;

  void _onConnectionState(BluetoothConnectionState s) {
    _log('Connection state: ${s.name}');
    if (s == BluetoothConnectionState.disconnected) {
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError(StateError('disconnected'));
      }
      _pending.clear();
      if (_manualDisconnect) {
        _set(LinkState.idle);
      } else if (state != LinkState.error) {
        _autoReconnect();
      }
    }
  }

  /// Keeps trying until the person disconnects manually (e.g. strap out of range
  /// during a run). Waits at most 15 s between attempts.
  Future<void> _autoReconnect() async {
    if (_reconnecting || device == null) return;
    _reconnecting = true;
    const delays = [1, 2, 4, 8, 15];
    while (!_manualDisconnect && state != LinkState.ready) {
      _set(LinkState.reconnecting);
      final wait = delays[_reconnectAttempt < delays.length ? _reconnectAttempt : delays.length - 1];
      _reconnectAttempt++;
      _log('Reconnect attempt $_reconnectAttempt in ${wait}s');
      await Future.delayed(Duration(seconds: wait));
      if (_manualDisconnect) break;
      await connect(device!);
    }
    _reconnectAttempt = 0;
    _reconnecting = false;
  }

  /// Try the strap this phone used last time, without scanning.
  Future<void> connectToLast() async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(_prefKey);
    if (id == null) return;
    if (!await _ensurePermissions() || !await _ensureAdapterOn()) return;
    await connect(BluetoothDevice.fromId(id));
  }

  Future<String?> lastDeviceId() async => (await SharedPreferences.getInstance()).getString(_prefKey);

  Future<void> disconnect({bool forget = false}) async {
    _manualDisconnect = true;
    try {
      await device?.disconnect();
    } catch (_) {}
    if (forget) {
      (await SharedPreferences.getInstance()).remove(_prefKey);
      device = null;
    }
    _set(LinkState.idle);
  }

  Future<void> readRssi() async {
    try {
      rssi = await device?.readRssi();
      notifyListeners();
    } catch (_) {}
  }

  // ----------------------------------------------------------------- writes
  int _nextSeq() {
    final s = _seq;
    _seq = (_seq % 255) + 1;
    return s;
  }

  Future<void> _writeRaw(List<int> bytes, {required String label}) {
    final c = _cmdWrite;
    if (c == null) return Future.error(StateError('Not connected'));
    // Serialise writes so patterns/intervals can't interleave.
    final next = _writeChain.then((_) async {
      _log('TX $label: ${toHex(bytes)}');
      final noResp = !c.properties.write && c.properties.writeWithoutResponse;
      await c.write(bytes, withoutResponse: noResp);
    });
    _writeChain = next.catchError((_) {});
    return next;
  }

  void _onNotify(List<int> value) {
    for (final f in _reasm.feed(value)) {
      final r = parseResponse(Uint8List.fromList(f));
      _log('RX ${toHex(f)}${r == null ? "" : "  -> cmd ${r.cmd} origin#${r.originSeq} ${r.resultName}"}');
      if (r == null) continue;
      if (_awaitedHello != null && !_awaitedHello!.isCompleted && r.cmd == WhoopCmd.clientHello) {
        _awaitedHello!.complete(r);
      }
      final p = _pending.remove(r.originSeq);
      if (p != null && !p.isCompleted) p.complete(r);
    }
  }

  /// Sends one haptic command and returns the strap's reply (null = no reply).
  /// A "success" reply means the strap accepted the command; whether you FEEL
  /// it is the real test.
  Future<ParsedResponse?> buzz(int pulses, {bool experimental = false, int b2 = 0x98}) async {
    if (!isReady) throw StateError('Strap not connected');
    final seq = _nextSeq();
    final done = Completer<ParsedResponse>();
    _pending[seq] = done;
    await _writeRaw(buildHapticFrame(seq: seq, pulses: pulses, experimental: experimental, b2: b2), label: 'BUZZ x$pulses b2=0x${b2.toRadixString(16)}${experimental ? ' (experimental)' : ''}');
    try {
      final r = await done.future.timeout(const Duration(seconds: 2));
      lastResponse = '${r.resultName} (${DateTime.now().toIso8601String().substring(11, 19)})';
      notifyListeners();
      return r;
    } on TimeoutException {
      _pending.remove(seq);
      lastResponse = 'no reply';
      notifyListeners();
      return null;
    }
  }

  /// Best-effort stop: sends STOP_HAPTICS twice. The opcode is community-sourced
  /// and unverified on a WHOOP 5.0, so callers must also cut the link.
  Future<void> sendStop() async {
    if (_cmdWrite == null) return;
    for (var i = 0; i < 2; i++) {
      try {
        await _writeRaw(buildStopHapticsFrame(seq: _nextSeq()), label: 'STOP');
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Diagnostics: send arbitrary bytes. If they start with AA 01 they are
  /// written as-is; otherwise they are treated as [cmd][body...] and wrapped.
  Future<void> sendRawHex(String hex, {required bool wrap}) async {
    final b = fromHex(hex);
    if (b == null) throw const FormatException('Invalid hex');
    final out = wrap ? buildCommandFrame(seq: _nextSeq(), command: b.first, body: b.sublist(1)) : b;
    await _writeRaw(out, label: 'RAW');
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _notifySub0?.cancel();
    _notifySub1?.cancel();
    _bondSub?.cancel();
    super.dispose();
  }
}

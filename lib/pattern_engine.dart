import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'whoop_ble.dart';

/// One burst: [pulses] (1..8, sent as a single strap command) then [pauseMs].
/// The strap decides how long each pulse lasts; per-pulse duration/strength is
/// NOT controllable (those bytes are undocumented).
class BuzzStep {
  BuzzStep(this.pulses, this.pauseMs);
  int pulses;
  int pauseMs;
}

class VibePattern {
  VibePattern(this.name, this.steps, {this.repeats = 1});
  String name;
  List<BuzzStep> steps;
  int repeats;

  VibePattern copy() => VibePattern(name, steps.map((s) => BuzzStep(s.pulses, s.pauseMs)).toList(), repeats: repeats);

  static List<VibePattern> presets() => [
        VibePattern('Single', [BuzzStep(1, 0)]),
        VibePattern('Double', [BuzzStep(2, 0)]),
        VibePattern('Triple', [BuzzStep(3, 0)]),
        VibePattern('SOS-ish', [BuzzStep(1, 700), BuzzStep(1, 700), BuzzStep(1, 1500), BuzzStep(3, 0)]),
      ];
}

/// Runs patterns and interval mode. Safety rules: at most 3 pulses per command,
/// at most 10 repetitions, interval mode ends by itself after 30 minutes, and
/// [panicStop] cancels everything, sends the best-effort stop command and can
/// cut the Bluetooth link.
class PatternEngine extends ChangeNotifier {
  PatternEngine(this.ble);
  final WhoopController ble;

  bool running = false; // a pattern is executing
  bool intervalOn = false;
  int intervalSeconds = 5;
  String? lastError;
  int sent = 0;

  static const maxRepeats = 10;
  static const intervalMaxMinutes = 30;

  bool _cancel = false;
  Timer? _watchdog;
  Timer? _timer;
  Completer<void>? _sleep;

  Future<void> _wait(int ms) async {
    if (ms <= 0) return;
    _sleep = Completer<void>();
    final t = Timer(Duration(milliseconds: ms), () {
      if (!(_sleep?.isCompleted ?? true)) _sleep!.complete();
    });
    await _sleep!.future;
    t.cancel();
  }

  /// Minimum spacing after a burst so the next command doesn't pile onto a
  /// still-running one. Pulse length is unmeasured; 350 ms/pulse is a guess,
  /// adjust after testing on your strap.
  static int settleMs(int pulses) => 350 * pulses + 200;

  Future<void> run(VibePattern p) async {
    if (running) return;
    running = true;
    _cancel = false;
    lastError = null;
    notifyListeners();
    try {
      for (var r = 0; r < p.repeats.clamp(1, maxRepeats) && !_cancel; r++) {
        for (final s in p.steps) {
          if (_cancel) break;
          await ble.buzz(s.pulses);
          sent++;
          await _wait(s.pauseMs + settleMs(s.pulses));
        }
      }
    } catch (e) {
      lastError = e.toString();
    } finally {
      running = false;
      notifyListeners();
    }
  }

  void startInterval(VibePattern p, int seconds) {
    stop();
    intervalSeconds = seconds;
    intervalOn = true;
    WakelockPlus.enable(); // timers stop when the app is suspended; see README
    Future<void> tick() async {
      if (running) return; // skip if the last run hasn't finished
      await run(p.copy());
    }

    tick();
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => tick());
    _watchdog = Timer(const Duration(minutes: intervalMaxMinutes), stop);
    notifyListeners();
  }

  void stop() {
    _cancel = true;
    _timer?.cancel();
    _timer = null;
    _watchdog?.cancel();
    _watchdog = null;
    if (!(_sleep?.isCompleted ?? true)) _sleep!.complete();
    if (intervalOn) WakelockPlus.disable();
    intervalOn = false;
    notifyListeners();
  }

  /// Big red button: cancel everything unsent, send the stop command, and
  /// (optionally) drop the Bluetooth link so nothing more can be sent.
  Future<void> panicStop({bool disconnect = false}) async {
    stop();
    await ble.sendStop();
    if (disconnect) {
      await ble.disconnect();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

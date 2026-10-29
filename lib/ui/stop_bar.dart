import 'package:flutter/material.dart';

import '../pattern_engine.dart';
import '../whoop_ble.dart';

/// Always-visible red STOP bar (shown on every tab).
class StopBar extends StatelessWidget {
  const StopBar({super.key, required this.ble, required this.engine});
  final WhoopController ble;
  final PatternEngine engine;

  Future<void> _stop(BuildContext context) async {
    // Cancel everything unsent first (instant), then ask the strap to stop.
    engine.stop();
    final sending = engine.panicStop();
    showStillBuzzingSheet(context, ble: ble, engine: engine);
    await sending;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFF453A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => _stop(context),
          icon: const Icon(Icons.stop_circle_outlined, size: 26),
          label: const Text('STOP VIBRATION',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        ),
      ),
    );
  }
}

void showStillBuzzingSheet(BuildContext context,
    {required WhoopController ble, required PatternEngine engine}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF0E0E0E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Stop sent', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text(
          'All queued buzzes were cancelled and a stop command was sent to the strap. '
          'That stop command is community-sourced and not confirmed on the WHOOP 5.0.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        const SizedBox(height: 16),
        const Text('Still buzzing?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text(
          '1. Tap the button below to cut the Bluetooth link.\n'
          '2. Official WHOOP app: device icon > Device Settings > Advanced > reboot. This stopped a stuck buzz for you.\n'
          '3. Put the strap on its charger or battery pack.\n'
          '4. Double-tap with the official app open (worked once, not always).',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await engine.panicStop(disconnect: true);
            },
            icon: const Icon(Icons.bluetooth_disabled),
            label: const Text('CUT THE CONNECTION'),
          ),
        ),
      ]),
    ),
  );
}

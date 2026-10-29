import 'package:flutter/material.dart';

import '../whoop_ble.dart';

({Color color, String text}) describe(WhoopController b) {
  switch (b.state) {
    case LinkState.ready:
      return b.helloAcked
          ? (color: const Color(0xFF30D158), text: 'Connected')
          : (color: const Color(0xFFFFB020), text: 'Connected - link not confirmed');
    case LinkState.scanning:
      return (color: const Color(0xFF0A84FF), text: 'Scanning');
    case LinkState.connecting:
      return (color: const Color(0xFF0A84FF), text: 'Connecting');
    case LinkState.discovering:
      return (color: const Color(0xFF0A84FF), text: 'Reading services');
    case LinkState.bonding:
      return (color: const Color(0xFFFFB020), text: 'Pairing - accept the prompt');
    case LinkState.handshaking:
      return (color: const Color(0xFF0A84FF), text: 'Handshake');
    case LinkState.reconnecting:
      return (color: const Color(0xFFFFB020), text: 'Reconnecting');
    case LinkState.error:
      return (color: const Color(0xFFFF453A), text: 'Error');
    case LinkState.idle:
      return (color: const Color(0xFF6E6E73), text: 'Not connected');
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.ble, {super.key, this.onTap});
  final WhoopController ble;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = describe(ble);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF2A2A2A)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: d.color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Flexible(child: Text(d.text, style: const TextStyle(fontSize: 13, letterSpacing: 0.3))),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';

const appVersion = '0.5.1';

/// Opens the About sheet. Pass a context that sits below MaterialApp.
void showAboutSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF0E0E0E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Row(children: [
            Icon(Icons.vibration, size: 32),
            SizedBox(width: 12),
            Text('WHOOP Buzz',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          const Text('Version $appVersion',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 20),
          _section('What it does',
              'Connects to your WHOOP 5.0 over Bluetooth and lets you trigger the strap\'s vibration manually: a single buzz, custom patterns, or repeating at an interval.'),
          _section('Tabs',
              'Control: vibrate, patterns and interval mode.\nDevice: scan, connect, status and pairing tips.\nDiagnostics: raw log and a raw command sender.\nLab: experiments to find which haptic byte sets the pulse spacing.'),
          _section('Good to know',
              '• The strap keeps one encrypted bond. If connecting fails with "Authentication is insufficient", quit the official WHOOP app and re-pair.\n'
              '• Interval mode keeps the screen awake. If the strap goes out of range, buzzes pause and the app keeps reconnecting until you disconnect; buzzes resume when it is back. Each buzz is sent by the phone, so nothing buzzes while you are out of range.\n'
              '• Sideloaded apps from a free Apple ID expire after 7 days and need reinstalling.'),
          _section('Status',
              'The vibration command comes from community reverse-engineering and is still experimental. The strap-side stop command is also unconfirmed, so the red STOP bar also cancels everything queued, and "Cut the connection" is a fallback. If a buzz sticks, reboot the strap in the official WHOOP app (device icon > Device Settings > Advanced). Buzzes are capped at 3 pulses and interval mode ends after 30 minutes.'),
          _section('Disclaimer',
              'Unofficial. Not made by or affiliated with WHOOP, Inc. Use at your own risk.'),
        ],
      ),
    ),
  );
}

Widget _section(String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(body, style: const TextStyle(color: Colors.white70, height: 1.4)),
      ]),
    );

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pattern_engine.dart';
import '../whoop_ble.dart';
import 'status_pill.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key, required this.ble, required this.engine, required this.goDevice});
  final WhoopController ble;
  final PatternEngine engine;
  final VoidCallback goDevice;
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final presets = VibePattern.presets();
  late VibePattern selected = presets[0].copy();
  int presetIndex = 0; // -1 = custom
  static const intervals = [1, 2, 5, 10, 30];
  int trainPulses = 3;
  int intervalSel = 1; // 1 pulse every second by default (preset 'Single')

  WhoopController get ble => widget.ble;
  PatternEngine get eng => widget.engine;

  Future<void> _vibrate() async {
    if (!ble.isReady) {
      _snack('Not connected. Open the Device tab.');
      return;
    }
    await eng.run(selected.copy());
    if (eng.lastError != null) _snack(eng.lastError!);
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([ble, eng]),
      builder: (context, _) {
        final ready = ble.isReady;
        return ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
          Center(child: StatusPill(ble, onTap: widget.goDevice)),
          const SizedBox(height: 28),
          Center(
            child: GestureDetector(
              onTap: _vibrate,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 230,
                height: 230,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ready ? Colors.white : Colors.transparent,
                  border: Border.all(color: ready ? Colors.white : const Color(0xFF3A3A3A), width: 2),
                ),
                alignment: Alignment.center,
                child: Text('VIBRATE\nNOW',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 30,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: ready ? Colors.black : const Color(0xFF6E6E73))),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              ble.lastResponse == null ? ' ' : 'Strap reply: ${ble.lastResponse}',
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'The red STOP bar at the bottom is always available. Every buzz is capped at 3 pulses, '
              'patterns at 10 repeats, and interval mode ends by itself after 30 minutes.',
              style: TextStyle(color: Color(0xFF6E6E73), fontSize: 11),
            ),
          ),
          const SizedBox(height: 26),
          _section('PATTERN'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < presets.length; i++)
              ChoiceChip(
                label: Text(presets[i].name),
                selected: presetIndex == i,
                onSelected: (_) => setState(() {
                  presetIndex = i;
                  selected = presets[i].copy();
                }),
              ),
            ChoiceChip(
              label: const Text('Custom'),
              selected: presetIndex == -1,
              onSelected: (_) => setState(() {
                presetIndex = -1;
                selected.name = 'Custom';
              }),
            ),
          ]),
          const SizedBox(height: 12),
          _editor(),
          const SizedBox(height: 26),
          const SizedBox(height: 26),
          _section('1 PULSE PER SECOND (STRAP RUNS IT)'),
          const Text(
            'Uses the byte setting you found (b2 = 0x80). The strap plays the pulses by itself, about 1 per second, '
            'so the phone does not have to stay close. The STOP bar cannot end a long one; reboot the strap in the official WHOOP app.',
            style: TextStyle(color: Color(0xFF6E6E73), fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final n in [2, 3, 4, 6, 8])
              ChoiceChip(
                label: Text('$n pulses'),
                selected: trainPulses == n,
                onSelected: (_) => setState(() => trainPulses = n),
              ),
          ]),
          const SizedBox(height: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: () async {
              if (!ready) {
                _snack('Not connected. Open the Device tab.');
                return;
              }
              try {
                await widget.ble.buzz(trainPulses, experimental: true, b2: 0x80);
              } catch (e) {
                _snack(e.toString());
              }
            },
            child: const Text('SEND 1/SEC TRAIN'),
          ),
          const SizedBox(height: 26),
          _section('LONG BUZZ (EXPERIMENTAL)'),
          const Text(
            'Sends the 12 bytes you saved in the Lab tab (default: 8 loops). It may keep buzzing on its own and the app cannot stop it. '
            'To stop it: reboot the strap in the official WHOOP app (device icon > Device Settings > Advanced). '
            'Pulse timing cannot be changed; for 1 pulse per second use the interval below (phone must be in range).',
            style: TextStyle(color: Color(0xFF6E6E73), fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: () async {
              if (!ready) {
                _snack('Not connected. Open the Device tab.');
                return;
              }
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Send long buzz?'),
                  content: const Text(
                      'It may keep buzzing until you reboot the strap in the official WHOOP app. The STOP bar will not end it.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
                  ],
                ),
              );
              if (ok == true) {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final hex = prefs.getString('long_body_hex') ?? '01 2F 98 00 00 00 00 00 00 00 00 07';
                  await widget.ble.sendRawHex('13 $hex', wrap: true);
                } catch (e) {
                  _snack(e.toString());
                }
              }
            },
            child: const Text('SEND LONG BUZZ'),
          ),
          const SizedBox(height: 26),
          _section('INTERVAL MODE'),
          Wrap(spacing: 8, children: [
            for (final s in intervals)
              ChoiceChip(
                label: Text('${s}s'),
                selected: intervalSel == s,
                onSelected: eng.intervalOn ? null : (_) => setState(() => intervalSel = s),
              ),
          ]),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: eng.intervalOn ? const Color(0xFFFF453A) : Colors.white,
                foregroundColor: eng.intervalOn ? Colors.white : Colors.black),
            onPressed: () {
              if (eng.intervalOn) {
                eng.stop();
              } else if (ready) {
                eng.startInterval(selected, intervalSel);
              } else {
                _snack('Not connected. Open the Device tab.');
              }
            },
            child: Text(eng.intervalOn ? 'STOP INTERVAL (every ${eng.intervalSeconds}s)' : 'START INTERVAL'),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Interval mode keeps the screen awake and runs only while the app is open. '
              'Short intervals with long patterns are skipped while the previous burst is still running. '
              'Intervals under 5 s use noticeably more battery on the strap.',
              style: TextStyle(color: Color(0xFF6E6E73), fontSize: 11),
            ),
          ),
          const SizedBox(height: 8),
          Text('Bursts sent this session: ${eng.sent}', style: const TextStyle(color: Color(0xFF6E6E73), fontSize: 11)),
        ]);
      },
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(fontSize: 12, letterSpacing: 2, color: Color(0xFF8E8E93))),
      );

  Widget _editor() {
    final custom = presetIndex == -1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF0E0E0E), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < selected.steps.length; i++) ...[
          Row(children: [
            Text('Burst ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            if (custom && selected.steps.length > 1)
              IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => selected.steps.removeAt(i))),
          ]),
          _slider('Pulses', selected.steps[i].pulses.toDouble(), 1, 3, 2, '${selected.steps[i].pulses}', custom,
              (v) => setState(() => selected.steps[i].pulses = v.round())),
          _slider('Pause after', selected.steps[i].pauseMs.toDouble(), 0, 5000, 50,
              '${(selected.steps[i].pauseMs / 1000).toStringAsFixed(1)} s', custom,
              (v) => setState(() => selected.steps[i].pauseMs = (v / 100).round() * 100)),
          const Divider(height: 18, color: Color(0xFF222222)),
        ],
        _slider('Repetitions', selected.repeats.toDouble(), 1, 10, 9, '${selected.repeats}x', custom,
            (v) => setState(() => selected.repeats = v.round())),
        if (custom)
          TextButton.icon(
            onPressed: selected.steps.length >= 12 ? null : () => setState(() => selected.steps.add(BuzzStep(1, 500))),
            icon: const Icon(Icons.add),
            label: const Text('Add burst'),
          ),
        const Text(
          'A "pulse" is one strap-defined buzz; 1-3 pulses go out as one command. '
          'Per-pulse length and strength are not controllable (undocumented bytes).',
          style: TextStyle(color: Color(0xFF6E6E73), fontSize: 11),
        ),
      ]),
    );
  }

  Widget _slider(String label, double v, double min, double max, int div, String text, bool enabled,
      ValueChanged<double> on) {
    return Row(children: [
      SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13))),
      Expanded(child: Slider(value: v.clamp(min, max), min: min, max: max, divisions: div, onChanged: enabled ? on : null)),
      SizedBox(width: 48, child: Text(text, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
    ]);
  }
}

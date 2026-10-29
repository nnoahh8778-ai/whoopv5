import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' show CharacteristicProperties;

import '../whoop_ble.dart';
import '../whoop_protocol.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.ble});
  final WhoopController ble;
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final hex = TextEditingController(text: '13 01 2F 98 00 00 00 00 00 00 00 00 00');
  bool wrap = true;
  String? result;

  WhoopController get ble => widget.ble;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ble,
      builder: (context, _) => ListView(padding: const EdgeInsets.all(20), children: [
        const Text('DIAGNOSTICS', style: TextStyle(fontSize: 12, letterSpacing: 2, color: Color(0xFF8E8E93))),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => ble.startScan(all: true),
          child: const Text('Scan ALL BLE devices (find your strap by name / RSSI)'),
        ),
        if (ble.showAllDevices)
          for (final r in ble.scanResults.take(25))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(r.device.platformName.isEmpty ? '(unnamed)' : r.device.platformName),
              subtitle: Text('${r.device.remoteId.str}  RSSI ${r.rssi}\nsvc: ${r.advertisementData.serviceUuids.map((g) => g.str).join(", ")}'),
              isThreeLine: true,
              onTap: () => ble.connect(r.device),
            ),
        const SizedBox(height: 16),
        _title('GATT SERVICES (${ble.services.length})'),
        if (ble.services.isEmpty) const Text('Connect first.', style: TextStyle(color: Color(0xFF6E6E73))),
        for (final s in ble.services)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.uuid.str128, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700)),
              for (final c in s.characteristics)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text('${c.uuid.str128}  [${_props(c.properties)}]',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFAAAAAA))),
                ),
            ]),
          ),
        const SizedBox(height: 16),
        _title('RAW COMMAND (EXPERIMENTAL)'),
        TextField(
          controller: hex,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: wrap,
          onChanged: (v) => setState(() => wrap = v),
          title: const Text('Wrap as command frame', style: TextStyle(fontSize: 13)),
          subtitle: const Text('On: first byte = opcode, rest = body (envelope + CRCs added). Off: send bytes exactly as typed.',
              style: TextStyle(fontSize: 11)),
        ),
        const Text(
          'Unknown opcodes can change strap settings or worse. Known-destructive commands (firmware load, trim, DFU, '
          'config writes) must never be sent. Stay with the haptic opcode 0x13 unless you know what you are doing.',
          style: TextStyle(color: Color(0xFFFFB020), fontSize: 11),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: ble.isReady
              ? () async {
                  try {
                    await ble.sendRawHex(hex.text, wrap: wrap);
                    setState(() => result = 'sent');
                  } catch (e) {
                    setState(() => result = '$e');
                  }
                }
              : null,
          child: const Text('SEND'),
        ),
        if (result != null) Text(result!, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 16),
        Row(children: [
          _title('LOG'),
          const Spacer(),
          TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: ble.log.join('\n'))), child: const Text('Copy')),
          TextButton(onPressed: () => setState(ble.log.clear), child: const Text('Clear')),
        ]),
        Container(
          height: 280,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF0E0E0E), borderRadius: BorderRadius.circular(10)),
          child: ListView.builder(
            reverse: true,
            itemCount: ble.log.length,
            itemBuilder: (_, i) => Text(ble.log[ble.log.length - 1 - i],
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: Color(0xFFBBBBBB))),
          ),
        ),
        const SizedBox(height: 6),
        Text('Self-test: CLIENT_HELLO = ${toHex(buildClientHello())}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF6E6E73))),
      ]),
    );
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 12, letterSpacing: 2, color: Color(0xFF8E8E93))),
      );

  String _props(CharacteristicProperties p) => [
        if (p.read) 'read',
        if (p.write) 'write',
        if (p.writeWithoutResponse) 'writeNR',
        if (p.notify) 'notify',
        if (p.indicate) 'indicate',
      ].join(',');
}

import 'package:flutter/material.dart';

import '../whoop_ble.dart';
import 'status_pill.dart';

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key, required this.ble});
  final WhoopController ble;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ble,
      builder: (context, _) {
        final connected = ble.isReady;
        final busy = {LinkState.connecting, LinkState.discovering, LinkState.bonding, LinkState.handshaking, LinkState.reconnecting}
            .contains(ble.state);
        return ListView(padding: const EdgeInsets.all(20), children: [
          Center(child: StatusPill(ble)),
          if (ble.error != null) ...[
            const SizedBox(height: 14),
            _card([
              Text(ble.error!, style: const TextStyle(color: Color(0xFFFF453A))),
              if (ble.hint != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(ble.hint!)),
            ]),
          ] else if (ble.hint != null) ...[
            const SizedBox(height: 14),
            _card([Text(ble.hint!)]),
          ],
          const SizedBox(height: 18),
          if (!connected)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: busy ? null : () => ble.state == LinkState.scanning ? ble.stopScan() : ble.startScan(),
              child: Text(ble.state == LinkState.scanning ? 'STOP SCAN' : 'SCAN FOR WHOOP'),
            ),
          if (!connected && !busy)
            TextButton(onPressed: ble.connectToLast, child: const Text('Reconnect to last strap')),
          for (final r in ble.scanResults)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.device.platformName.isEmpty ? '(unnamed)' : r.device.platformName),
              subtitle: Text('${r.device.remoteId.str}   RSSI ${r.rssi}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy ? null : () => ble.connect(r.device),
            ),
          if (connected || busy) ...[
            const SizedBox(height: 8),
            _card([
              _row('Device', ble.device?.platformName.isEmpty ?? true ? '(unnamed)' : ble.device!.platformName),
              _row('Address / ID', ble.device?.remoteId.str ?? '-'),
              _row('State', describe(ble).text),
              _row('WHOOP 5.0 service', ble.serviceFound ? 'found' : 'not found'),
              _row('CLIENT_HELLO ack', ble.helloAcked ? 'yes' : 'no'),
              _row('Bond', ble.bondText),
              _row('MTU', ble.mtu?.toString() ?? '-'),
              _row('RSSI', ble.rssi?.toString() ?? '-'),
              _row('Last haptic reply', ble.lastResponse ?? '-'),
            ]),
            Row(children: [
              TextButton(onPressed: ble.readRssi, child: const Text('Refresh RSSI')),
              const Spacer(),
              TextButton(onPressed: () => ble.disconnect(), child: const Text('Disconnect')),
              TextButton(onPressed: () => ble.disconnect(forget: true), child: const Text('Forget')),
            ]),
          ],
          const SizedBox(height: 18),
          const Text(
            'Pairing tips\n'
            '- The strap keeps ONE encrypted bond. Quit the official WHOOP app and turn off Bluetooth on the phone it was bonded to.\n'
            '- Tap the strap repeatedly until the LED flashes blue (pairing mode).\n'
            '- Pairing here takes the bond away from the official app; it will ask to re-pair next time you open it.\n'
            '- Android: also remove any old "WHOOP" entry from system Bluetooth settings first.',
            style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12, height: 1.4),
          ),
        ]);
      },
    );
  }

  Widget _card(List<Widget> c) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFF0E0E0E), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: c),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 140, child: Text(k, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

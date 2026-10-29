import 'package:flutter/material.dart';

import 'pattern_engine.dart';
import 'ui/about_sheet.dart';
import 'ui/control_screen.dart';
import 'ui/device_screen.dart';
import 'ui/diagnostics_screen.dart';
import 'ui/lab_screen.dart';
import 'ui/stop_bar.dart';
import 'whoop_ble.dart';

void main() => runApp(const WhoopBuzzApp());

class WhoopBuzzApp extends StatefulWidget {
  const WhoopBuzzApp({super.key});
  @override
  State<WhoopBuzzApp> createState() => _WhoopBuzzAppState();
}

class _WhoopBuzzAppState extends State<WhoopBuzzApp> with WidgetsBindingObserver {
  final ble = WhoopController();
  late final engine = PatternEngine(ble);
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ble.connectToLast(); // silently retry the last strap on launch
  }

  // No cancel on pause: interval mode must keep going when the screen locks.
  // It still ends by itself (30 min) and the STOP bar always works.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    engine.dispose();
    ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      ControlScreen(ble: ble, engine: engine, goDevice: () => setState(() => tab = 1)),
      DeviceScreen(ble: ble),
      DiagnosticsScreen(ble: ble),
      LabScreen(ble: ble),
    ];
    return MaterialApp(
      title: 'WHOOP Buzz',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(primary: Colors.white, surface: Color(0xFF0E0E0E)),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: Scaffold(
        body: Column(children: [
          Expanded(child: Builder(
          builder: (ctx) => SafeArea(
            child: Stack(children: [
              pages[tab],
              Positioned(
                top: 0,
                right: 4,
                child: IconButton(
                  tooltip: 'About',
                  icon: const Icon(Icons.info_outline, color: Colors.white70),
                  onPressed: () => showAboutSheet(ctx),
                ),
              ),
            ]),
          ),
          )),
          StopBar(ble: ble, engine: engine),
        ]),
        bottomNavigationBar: NavigationBar(
          backgroundColor: Colors.black,
          indicatorColor: const Color(0xFF222222),
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.vibration), label: 'Control'),
            NavigationDestination(icon: Icon(Icons.bluetooth), label: 'Device'),
            NavigationDestination(icon: Icon(Icons.bug_report_outlined), label: 'Diagnostics'),
            NavigationDestination(icon: Icon(Icons.science_outlined), label: 'Lab'),
          ],
        ),
      ),
    );
  }
}

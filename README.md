# WHOOP Buzz

Flutter app (iOS + Android) that sends haptic commands to a **WHOOP 5.0** strap over BLE.
Dark UI: Control, Device, Diagnostics tabs.

## STATUS: read this first

| Item | Status |
|---|---|
| BLE service / characteristic IDs (`fd4b0001` service; `0002` write, `0003` responses) | From community reverse engineering of the official app. Characteristics are matched by 8-digit prefix at runtime, not assumed. |
| Frame format, CRC16/CRC32, 4-byte padding, CLIENT_HELLO | **Checked here**: builder reproduces the published CLIENT_HELLO frame byte for byte (`python3 tool/verify_frames.py`). |
| Haptic command (opcode `0x13`, 12-byte body, last byte = pulses-1) | Taken from a community report of working on a real 5/MG (tanarchytan/noop PR #6) and whoop-rs. **Not verified by me on hardware.** The meaning of body bytes `01 2F 98` is unknown. |
| This app on a real strap | **UNTESTED.** I had no strap, no Flutter SDK and no network in my build sandbox, so the Dart code has not been compiled or run. Expect to fix small compile errors. |
| Stop button | Cancels queued bursts and timers only. No strap-side "stop haptics" command is documented. |
| Per-pulse duration / strength | Not controllable (bytes undocumented). Pulses 1-8 per command. |
| Background operation | Interval mode runs only while the app is open (screen kept awake). |

**The acceptance test is you feeling the strap buzz.** The app shows the strap's reply
("success" = command accepted) but only your wrist confirms the motor ran.

## Why the pairing is awkward (real limitation)

The strap keeps **one** encrypted bond. If the official WHOOP app owns it, commands are refused
("Encryption is insufficient"). Pairing this app takes the bond away from the official app, which
will ask to re-pair later. Some Android phones refuse bonding (community issue NOOP #1635, cause
unknown); iOS tends to work. Live heart rate needs no bond, but haptics do.

## Setup

1. Install Flutter (3.22+), then in this folder:
   ```
   flutter create . --project-name whoop_buzz --platforms=android,ios
   flutter pub get
   ```
   (`flutter create .` generates the android/ios folders without touching `lib/`.)
2. **Android** `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:
   ```xml
   <uses-feature android:name="android.hardware.bluetooth_le" android:required="true"/>
   <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
   <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
   <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
   <uses-permission android:name="android.permission.WAKE_LOCK"/>
   ```
   Set `minSdkVersion 21` (or `flutter.minSdkVersion`) in `android/app/build.gradle`.
3. **iOS** `ios/Runner/Info.plist`:
   ```xml
   <key>NSBluetoothAlwaysUsageDescription</key>
   <string>Needed to send vibration commands to your WHOOP strap.</string>
   ```
   Use a real iPhone (no Bluetooth in the simulator) and set a signing team in Xcode.
4. Run: `flutter test` (protocol tests), then `flutter run` on a physical phone.

## First connection

1. Quit the official WHOOP app completely; turn Bluetooth off on any other phone using the strap.
2. Android: delete any old "WHOOP" entry in system Bluetooth settings.
3. Tap the strap repeatedly until the LED flashes blue.
4. Device tab > SCAN FOR WHOOP > tap the strap > accept the pairing prompt.
5. Success: status pill green "Connected" (CLIENT_HELLO acknowledged). Press VIBRATE NOW.

## Debugging

- Diagnostics tab > "Scan ALL" lists every BLE device with its advertised services; the strap may
  not advertise its name, so look for the strongest RSSI when it is on your wrist.
- GATT list must show a `fd4b0001-...` service with `fd4b0002` (write) and `fd4b0003` (notify).
  If not, you have a different device or a WHOOP 4.0 (service `61080001-...`, different protocol).
- Log shows every TX/RX frame in hex. Copy it when reporting problems. A reply of
  "unsupported" or "failure" to opcode 0x13 means the firmware rejects that frame.
- Green but no buzz: strap replied "success"? Then check strap battery / wear. No reply at all?
  The bond is probably not encrypted; redo the pairing steps.
- `python3 tool/verify_frames.py` prints the exact bytes the app sends, for comparison with
  captures from the official app (Android HCI snoop log + Wireshark).

## Alternatives if direct haptics fail on your firmware

The strap has a single on-strap alarm slot that buzzes at a set time (community report:
whoop-vault). Setting it needs the alarm command body, which is **not documented publicly**
(wearable5.0 lists it as missing), so it is not implemented here. Capturing the official app
setting an alarm would reveal it.

## Credits / licenses

Protocol facts from LeonardSEO/wearable5.0 (MIT), Sophonbot0/whoop-vault (MIT), NOOP and
whoop-rs (PolyForm Noncommercial; only public facts used, no code copied). Independent
interoperability project, not affiliated with WHOOP. Personal, non-commercial use on your own strap.

## iPhone from a Windows PC (no Mac)

See `.github/workflows/build-ios.yml`: a free GitHub macOS runner builds an unsigned IPA;
install it from Windows with Sideloadly (free Apple ID, app expires every 7 days).
Untested - expect to iterate on build errors.


## v0.2 - safety changes
- Red **STOP VIBRATION** bar on every screen: cancels all queued buzzes, sends a best-effort STOP_HAPTICS (opcode 0x7A, community-sourced, **unverified on 5.0**), then offers **Cut the connection**.
- Max 3 pulses per command (the old 8-pulse "Long" preset is gone), max 10 pattern repeats, interval mode auto-ends after 30 minutes, and leaving the app cancels everything queued.
- Honest limit: if the strap ignores the stop command, the only guaranteed fallbacks are cutting the link, charging the strap, or the official WHOOP app.
- About button (top-right info icon).

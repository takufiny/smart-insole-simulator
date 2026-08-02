# Testing Guide — Smart Insole

Test in four stages. Each stage isolates one failure domain, so when
something breaks you know which layer to look at.

---

## Stage 0 — Test the app with no hardware at all (start here)

The app ships with a built-in demo mode. `BleService.startDemo()`
synthesises a realistic heel-strike gait cycle at 10 Hz and walks a
circular GPS course, so the heatmap, strike analysis, score banner and
map polyline all animate exactly as they would from a real insole.

    cd flutter_app
    flutter pub get
    flutter run          # physical device or emulator both fine here

Tap **"Run in Demo Mode (no device)"** on the home screen.

Expected: heatmap pulses heel -> forefoot -> toe each ~0.8 s, strike
reads "Heel Striker", symmetry sits slightly below 100 (the simulator
under-loads the right forefoot by design), distance climbs, map draws a
growing circle.

This validates every layer except BLE and the firmware. Do this before
touching hardware — it separates UI bugs from radio bugs.

---

## Stage 1 — Firmware on the bench (serial only, no app)

Wire each FSR as a voltage divider. An FSR alone does nothing useful:
it is a variable resistor, so without the pulldown the ADC pin floats
and you will read garbage.

    3.3V ── FSR ──┬── ADC pin (34 / 35 / 32 / 33)
                  │
                  └── 10k resistor ── GND

GPS: NEO-6M VCC->3.3V, GND->GND, TX->GPIO16, RX->GPIO17.
Note the crossover — module TX goes to ESP32 RX.

Arduino IDE library versions matter:

  - ArduinoJson — install **6.x**, not 7.x. v7 removed
    `StaticJsonDocument` and the sketch will not compile.
  - TinyGPSPlus by Mikal Hart
  - ESP32 board package 2.x

Flash, open Serial Monitor at **115200**. You should see:

    [BOOT] SmartInsole Firmware v1.0
    [GPS] UART2 ready
    [BLE] Advertising as 'SmartInsole_01'
    [DATA] H:  12 FL:   8 FR:  10 T:   6 | pace:0.00 | dist:0.000 | 0.000000,0.000000

Press each sensor in turn and confirm the matching field jumps toward
4095. If a channel reads a constant ~4095 or ~0, that divider is
miswired. If all four move together, you have a shared-pin error.

GPS coordinates stay 0.000000 indoors — that is correct, not a fault.
The NEO-6M needs clear sky view and 30 s to several minutes for a cold
first fix. Its LED blinks once locked. Test GPS outdoors or by a window.

---

## Stage 2 — Verify BLE with a generic scanner (before the app)

Install **nRF Connect** (Nordic, free, iOS + Android). Scan for
`SmartInsole_01`, connect, expand service `6E400001-...`, find
characteristic `6E400003-...` and press the notify/subscribe arrow.

You should see a JSON string arriving 10x per second:

    {"h":1240,"fl":890,"fr":760,"t":420,"pace":0,"dist":0,...}

This is the highest-value debugging step. If nRF Connect sees the data
but your Flutter app does not, the firmware is fine and the bug is in
the app. If nRF Connect sees nothing, stay in the firmware.

---

## Stage 3 — App against real hardware

**BLE does not work on emulators or the iOS simulator.** You need a
physical phone. This is the single most common source of "it just says
scanning forever".

Android — add to `android/app/src/main/AndroidManifest.xml`:

    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />

Set `minSdkVersion 21` or higher in `android/app/build.gradle`.

iOS — add to `ios/Runner/Info.plist`:

    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Connects to your Smart Insole.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Shows your running route.</string>

Then:

    flutter run --release   # release avoids debug-build BLE timing flakiness

Expected sequence: Scanning -> Connecting -> auto-navigate to dashboard
-> heatmap responds within ~200 ms of pressing a sensor.

### If scanning never finds the device

The scan filters on **both** service UUID and the name prefix
`SmartInsole`, so both must match. On iOS `platformName` is sometimes
empty until after connecting, which makes the name check fail. If you
hit that, loosen the filter in `services/ble_service.dart` — drop the
`name.startsWith(...)` condition and rely on the service UUID, which is
already applied in `withServices`.

Also confirm nothing else is holding the connection. BLE peripherals
accept one central at a time — if nRF Connect is still connected from
Stage 2, the app cannot get in. Force-close it.

---

## Stage 4 — Map

Add your Google Maps API key, or the map renders as a blank grey grid
(this is the expected symptom of a missing key, not a code bug):

  - Android: `<meta-data android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_KEY"/>` inside `<application>` in the manifest.
  - iOS: `GMSServices.provideAPIKey("YOUR_KEY")` in `AppDelegate.swift`.

Enable "Maps SDK for Android" and "Maps SDK for iOS" in Google Cloud
Console. Demo mode exercises the polyline logic without going outside.

---

## Quick triage table

| Symptom | Most likely cause |
|---|---|
| Sketch will not compile, `StaticJsonDocument` unknown | ArduinoJson 7.x installed; downgrade to 6.x |
| One FSR channel pinned at 0 or 4095 | Missing/miswired 10k pulldown |
| All FSR channels read ~0 and never move | Sensors on ADC2 pins; ADC2 is dead while BLE runs |
| GPS lat/lng always 0 | No fix yet — go outdoors, wait for LED |
| Serial output is mojibake | Baud not set to 115200 |
| App stuck on Scanning | Emulator instead of real phone, missing Android 12 permissions, or nRF Connect still connected |
| Connects then drops immediately | ESP32 on weak USB power; use a decent supply |
| Heatmap frozen but values print on serial | Notify not subscribed — check BLE2902 descriptor present |
| Map is blank grey | Google Maps API key missing |

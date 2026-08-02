// ============================================================
// BleService — Manages BLE scanning, connection, and streaming
// Uses flutter_blue_plus ^1.31
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/insole_data.dart';

// ─── UUIDs must match ESP32 firmware ────────────────────────
const String kServiceUuid   = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kNotifyCharUuid= '6e400003-b5a3-f393-e0a9-e50e24dcca9e';
const String kDeviceNamePrefix = 'SmartInsole';

/// Connection lifecycle states surfaced to the UI.
enum BleStatus { idle, scanning, connecting, connected, disconnected, error }

class BleService extends ChangeNotifier {
  // ── Public observable state ──────────────────────────────
  BleStatus status = BleStatus.idle;
  InsoleData? latestData;
  String errorMessage = '';

  // ── Internals ────────────────────────────────────────────
  BluetoothDevice?      _device;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>?    _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  final PressureHistory history = PressureHistory(maxLength: 300);

  // Demo mode (no hardware required)
  Timer? _demoTimer;
  bool get isDemoMode => _demoTimer != null;

  // ── Stream controller so screens can react to new frames ─
  final _dataController = StreamController<InsoleData>.broadcast();
  Stream<InsoleData> get dataStream => _dataController.stream;

  // ─── Start BLE scan (max 10 s) ──────────────────────────
  Future<void> startScan() async {
    if (status == BleStatus.scanning) return;

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _setError('Bluetooth is off. Please enable it.');
      return;
    }

    _setStatus(BleStatus.scanning);
    errorMessage = '';
    notifyListeners();

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withServices: [Guid(kServiceUuid)],
    );

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        if (name.startsWith(kDeviceNamePrefix)) {
          debugPrint('[BLE] Found: $name — connecting…');
          FlutterBluePlus.stopScan();
          _connect(r.device);
          break;
        }
      }
    });

    // Scan timeout fallback
    Future.delayed(const Duration(seconds: 11), () {
      if (status == BleStatus.scanning) {
        _setError('No SmartInsole device found nearby.');
      }
    });
  }

  // ─── Connect to device ──────────────────────────────────
  Future<void> _connect(BluetoothDevice device) async {
    _device = device;
    _setStatus(BleStatus.connecting);

    try {
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 8));
    } catch (e) {
      _setError('Connection failed: $e');
      return;
    }

    // Monitor connection state for unexpected drops
    _connStateSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        debugPrint('[BLE] Connection lost — cleaning up');
        _cleanup();
        _setStatus(BleStatus.disconnected);
      }
    });

    await _discoverAndSubscribe(device);
  }

  // ─── Discover services and subscribe to notify char ─────
  Future<void> _discoverAndSubscribe(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final svc in services) {
        if (svc.uuid.toString().toLowerCase() == kServiceUuid) {
          for (final char in svc.characteristics) {
            if (char.uuid.toString().toLowerCase() == kNotifyCharUuid) {
              _notifyChar = char;
              await char.setNotifyValue(true);
              _notifySub = char.onValueReceived.listen(_onBleData);
              _setStatus(BleStatus.connected);
              debugPrint('[BLE] Subscribed to notify characteristic.');
              return;
            }
          }
        }
      }
      _setError('InsoleService UUID not found on device.');
    } catch (e) {
      _setError('Service discovery failed: $e');
    }
  }

  // ─── Parse incoming BLE bytes → InsoleData ──────────────
  void _onBleData(List<int> bytes) {
    try {
      final raw = utf8.decode(bytes);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final data = InsoleData.fromJson(json);
      latestData = data;
      history.add(data);
      _dataController.add(data);
      notifyListeners();
    } catch (e) {
      debugPrint('[BLE] Parse error: $e');
    }
  }

  // ─── Disconnect manually ────────────────────────────────
  Future<void> disconnect() async {
    await _device?.disconnect();
    _cleanup();
    _setStatus(BleStatus.idle);
  }

  // ─────────────────────────────────────────────────────────
  // DEMO MODE — synthesises a running gait at 10 Hz so the
  // entire UI can be tested with no ESP32 present.
  // Simulates a heel-striking runner at ~5:30 min/km looping
  // a small course. Call stopDemo() to end.
  // ─────────────────────────────────────────────────────────
  void startDemo() {
    if (_demoTimer != null) return;
    _cleanup();
    _setStatus(BleStatus.connected);

    final rnd = Random();
    var tick = 0;
    const baseLat = 13.7563, baseLng = 100.5018;
    var dist = 0.0;

    _demoTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      tick++;
      // Gait cycle ≈ 0.8 s → 8 ticks per stride
      final phase = (tick % 8) / 8.0;

      // Heel loads first, then forefoot, then toe pushes off
      double bell(double centre, double width) {
        final d = (phase - centre).abs();
        final w = d > 0.5 ? 1.0 - d : d;
        return exp(-pow(w / width, 2));
      }

      int q(double v) =>
          (v * 3400 + rnd.nextDouble() * 200).clamp(0, 4095).toInt();

      final heel = q(bell(0.12, 0.13));
      final ffL  = q(bell(0.42, 0.16) * 0.85);
      final ffR  = q(bell(0.45, 0.16) * 0.72);   // slight R under-load
      final toe  = q(bell(0.68, 0.14) * 0.60);

      const paceMin = 5.5;                        // 5:30 min/km
      final speed = 60.0 / paceMin;               // ≈10.9 km/h
      dist += speed / 3600.0 * 0.1;               // km per 100 ms

      // Walk a small circular course so the map polyline grows
      final ang = tick * 0.004;
      final data = InsoleData(
        heel: heel,
        forefootLeft: ffL,
        forefootRight: ffR,
        toe: toe,
        paceMinPerKm: paceMin + rnd.nextDouble() * 0.2 - 0.1,
        distanceKm: dist,
        latitude:  baseLat + sin(ang) * 0.004,
        longitude: baseLng + cos(ang) * 0.004,
        speedKmh: speed,
        timestamp: DateTime.now(),
      );

      latestData = data;
      history.add(data);
      _dataController.add(data);
      notifyListeners();
    });
  }

  void stopDemo() {
    _demoTimer?.cancel();
    _demoTimer = null;
    latestData = null;
    _setStatus(BleStatus.idle);
  }

  // ─── Internal helpers ───────────────────────────────────
  void _setStatus(BleStatus s) {
    status = s;
    notifyListeners();
  }

  void _setError(String msg) {
    errorMessage = msg;
    status = BleStatus.error;
    notifyListeners();
  }

  void _cleanup() {
    _demoTimer?.cancel();
    _demoTimer = null;
    _notifySub?.cancel();
    _connStateSub?.cancel();
    _scanSub?.cancel();
    _notifyChar = null;
    _device = null;
  }

  @override
  void dispose() {
    _cleanup();
    _dataController.close();
    super.dispose();
  }

  // ─── Convenience getters ─────────────────────────────────
  bool get isConnected => status == BleStatus.connected;
  String? get connectedDeviceName =>
      isDemoMode ? 'SmartInsole (Demo)' : _device?.platformName;
}

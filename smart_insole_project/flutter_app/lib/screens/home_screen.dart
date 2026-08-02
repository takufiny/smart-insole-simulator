// ============================================================
// HomeScreen — BLE scan & connection entry point
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import 'dashboard_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();

    // Auto-navigate to dashboard once connected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ble.isConnected) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
        );
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Logo / Icon ─────────────────────────────
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2332),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: const Color(0xFF00C86F).withOpacity(0.3),
                      blurRadius: 30, spreadRadius: 5)],
                ),
                child: const Icon(Icons.directions_run,
                    size: 64, color: Color(0xFF00C86F)),
              ),
              const SizedBox(height: 32),

              const Text('Smart Insole',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                      color: Colors.white, letterSpacing: -0.5)),
              const SizedBox(height: 8),
              Text('Real-time gait analysis & GPS tracking',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey[500])),

              const SizedBox(height: 56),

              // ── Status indicator ─────────────────────────
              _buildStatusRow(ble),
              const SizedBox(height: 32),

              // ── Connect button ───────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isButtonEnabled(ble.status)
                      ? () => ble.startScan()
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C86F),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  child: _buttonChild(ble.status),
                ),
              ),

              // ── Error message ────────────────────────────
              if (ble.status == BleStatus.error) ...[
                const SizedBox(height: 16),
                Text(ble.errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                TextButton(
                  onPressed: () => ble.startScan(),
                  child: const Text('Retry', style: TextStyle(color: Color(0xFF00C86F))),
                ),
              ],

              // ── Demo mode (test the whole UI with no hardware) ──
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: ble.status == BleStatus.scanning ||
                           ble.status == BleStatus.connecting
                    ? null
                    : () => ble.startDemo(),
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('Run in Demo Mode (no device)'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isButtonEnabled(BleStatus s) =>
      s == BleStatus.idle || s == BleStatus.disconnected || s == BleStatus.error;

  Widget _buttonChild(BleStatus s) {
    if (s == BleStatus.scanning || s == BleStatus.connecting) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
          SizedBox(width: 12),
          Text('Searching…'),
        ],
      );
    }
    return const Text('Connect to Insole');
  }

  Widget _buildStatusRow(BleService ble) {
    final (icon, text, color) = switch (ble.status) {
      BleStatus.idle        => (Icons.bluetooth,          'Ready to connect',   Colors.grey),
      BleStatus.scanning    => (Icons.bluetooth_searching,'Scanning for device…',const Color(0xFF00C86F)),
      BleStatus.connecting  => (Icons.link,               'Connecting…',        Colors.orange),
      BleStatus.connected   => (Icons.bluetooth_connected,'Connected!',         const Color(0xFF00C86F)),
      BleStatus.disconnected=> (Icons.bluetooth_disabled, 'Disconnected',       Colors.redAccent),
      BleStatus.error       => (Icons.error_outline,      'Error',              Colors.redAccent),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

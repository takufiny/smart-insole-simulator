// ============================================================
// DashboardScreen — Main running HUD with live heatmap
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../models/insole_data.dart';
import '../utils/pressure_analyzer.dart';
import '../widgets/foot_heatmap_painter.dart';
import '../widgets/metric_card.dart';
import 'map_screen.dart';
import 'home_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble  = context.watch<BleService>();
    final data = ble.latestData;

    // Disconnection guard
    if (!ble.isConnected && data == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: Row(children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(
                  color: ble.isConnected ? const Color(0xFF00C86F) : Colors.redAccent,
                  shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(ble.connectedDeviceName ?? 'Smart Insole',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'GPS Map',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MapScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled),
            tooltip: 'Disconnect',
            onPressed: () => ble.disconnect(),
          ),
        ],
      ),
      body: data == null
          ? _buildWaiting()
          : _buildContent(context, data, ble),
    );
  }

  Widget _buildWaiting() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: Color(0xFF00C86F)),
      SizedBox(height: 16),
      Text('Waiting for first packet…',
          style: TextStyle(color: Colors.grey)),
    ]),
  );

  Widget _buildContent(BuildContext ctx, InsoleData d, BleService ble) {
    final analysis = PressureAnalyzer.analyze(d);
    final sessionScore = PressureAnalyzer.sessionScore(ble.history);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ─── Session Score Banner ──────────────────────────
          _ScoreBanner(score: sessionScore, analysis: analysis),
          const SizedBox(height: 20),

          // ─── Heatmap + Zone Bars ───────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Foot heatmap
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2332),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(children: [
                    const Text('Pressure Map',
                        style: TextStyle(color: Colors.white70,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 260,
                      child: FootHeatmapWidget(data: d),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 12),

              // Zone pressure bars
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _ZoneBar(label: 'Heel',    norm: d.heelNorm,       color: const Color(0xFFFF4A4A)),
                    _ZoneBar(label: 'F-Left',  norm: d.forefootLNorm,  color: const Color(0xFFFFAA00)),
                    _ZoneBar(label: 'F-Right', norm: d.forefootRNorm,  color: const Color(0xFFFFAA00)),
                    _ZoneBar(label: 'Toe',     norm: d.toeNorm,        color: const Color(0xFF00C86F)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ─── Running Metrics Grid ──────────────────────────
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              MetricCard(
                label: 'Pace', value: d.paceFormatted, unit: '',
                icon: Icons.speed, accentColor: const Color(0xFF00C86F),
              ),
              MetricCard(
                label: 'Distance', value: d.distanceKm.toStringAsFixed(2), unit: 'km',
                icon: Icons.route, accentColor: Colors.blueAccent,
              ),
              MetricCard(
                label: 'Speed', value: d.speedKmh.toStringAsFixed(1), unit: 'km/h',
                icon: Icons.directions_run, accentColor: Colors.orangeAccent,
              ),
              MetricCard(
                label: 'Strike', value: analysis.label, unit: '',
                icon: Icons.analytics_outlined, accentColor: const Color(0xFFB57FFF),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ─── Coaching Tip ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2332),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF00C86F).withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.lightbulb_outline, color: Color(0xFF00C86F)),
              const SizedBox(width: 10),
              Expanded(child: Text(analysis.feedback,
                  style: const TextStyle(color: Colors.white70, fontSize: 13))),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── Session Score Banner ────────────────────────────────────
class _ScoreBanner extends StatelessWidget {
  final double score;
  final StrikeAnalysis analysis;
  const _ScoreBanner({required this.score, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final color = score >= 75
        ? const Color(0xFF00C86F)
        : score >= 55 ? Colors.orangeAccent : Colors.redAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          const Color(0xFF1A2332),
          color.withOpacity(0.15),
        ]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Running Quality', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${score.toStringAsFixed(0)}/100',
                style: TextStyle(color: color, fontSize: 36,
                    fontWeight: FontWeight.w900, letterSpacing: -1)),
          ]),
          const Spacer(),
          // Circular progress indicator
          SizedBox(
            width: 64, height: 64,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: score / 100,
                strokeWidth: 6,
                backgroundColor: Colors.white10,
                color: color,
              ),
              Icon(Icons.directions_run, color: color, size: 26),
            ]),
          ),
        ],
      ),
    );
  }
}

// ─── Zone Pressure Bar ───────────────────────────────────────
class _ZoneBar extends StatelessWidget {
  final String label;
  final double norm;
  final Color color;
  const _ZoneBar({required this.label, required this.norm, required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = (norm * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2332),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const Spacer(),
            Text('$pct%', style: TextStyle(color: color, fontSize: 11,
                fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: norm.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ]),
      ),
    );
  }
}

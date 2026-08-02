// ============================================================
// FootHeatmapPainter — Custom painter for real-time pressure heatmap
// ============================================================

import 'package:flutter/material.dart';
import '../models/insole_data.dart';
import '../utils/pressure_analyzer.dart';

/// CustomPainter that draws a foot silhouette with 4 colored zones.
/// Colors transition Green → Yellow → Red based on pressure intensity.
class FootHeatmapPainter extends CustomPainter {
  final InsoleData data;

  FootHeatmapPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Foot outline shape (simplified front view) ──────────
    final footPath = Path();
    footPath.moveTo(w * 0.4, h * 0.05);        // top-left toe
    footPath.quadraticBezierTo(w * 0.3, h * 0.1, w * 0.25, h * 0.25); // toe curve
    footPath.lineTo(w * 0.25, h * 0.4);        // midfoot
    footPath.quadraticBezierTo(w * 0.15, h * 0.6, w * 0.25, h * 0.8);  // heel curve
    footPath.lineTo(w * 0.4, h * 0.95);        // heel bottom
    footPath.lineTo(w * 0.6, h * 0.95);        // heel bottom right
    footPath.lineTo(w * 0.75, h * 0.8);        // heel curve right
    footPath.quadraticBezierTo(w * 0.85, h * 0.6, w * 0.75, h * 0.4);
    footPath.lineTo(w * 0.75, h * 0.25);
    footPath.quadraticBezierTo(w * 0.7, h * 0.1, w * 0.6, h * 0.05);
    footPath.close();

    // ── Outline stroke ──────────────────────────────────────
    canvas.drawPath(
      footPath,
      Paint()
        ..color = Colors.black38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // ── Fill outline with light base color ──────────────────
    canvas.drawPath(
      footPath,
      Paint()..color = Colors.grey[100]!,
    );

    // ── Draw pressure zones (4 circular regions) ────────────
    _drawPressureZone(canvas, Offset(w * 0.5, h * 0.12),  w * 0.15, data.toeNorm,        'Toe');
    _drawPressureZone(canvas, Offset(w * 0.35, h * 0.35), w * 0.12, data.forefootLNorm, 'FL');
    _drawPressureZone(canvas, Offset(w * 0.65, h * 0.35), w * 0.12, data.forefootRNorm, 'FR');
    _drawPressureZone(canvas, Offset(w * 0.5, h * 0.85),  w * 0.18, data.heelNorm,      'Heel');
  }

  void _drawPressureZone(Canvas canvas, Offset center, double radius, double norm, String label) {
    final (r, g, b) = PressureAnalyzer.pressureColor(norm);
    final color = Color.fromRGBO(r, g, b, 0.75);

    // Fill zone circle
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color,
    );

    // Border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Label text
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(FootHeatmapPainter old) => old.data != data;
}

/// Widget wrapper for the heatmap painter.
class FootHeatmapWidget extends StatelessWidget {
  final InsoleData data;

  const FootHeatmapWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: FootHeatmapPainter(data: data),
      size: const Size(200, 300),
    );
  }
}

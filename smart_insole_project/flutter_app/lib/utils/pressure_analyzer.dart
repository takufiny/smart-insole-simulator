// ============================================================
// PressureAnalyzer — Derives running quality score & insights
// ============================================================

import '../models/insole_data.dart';

/// Result of a single-frame strike analysis.
class StrikeAnalysis {
  final StrikeType type;
  final double qualityScore;      // 0–100
  final String label;             // e.g. "Heel Striker"
  final String feedback;          // coaching tip
  final double symmetryScore;     // 0–100 (L/R balance)

  const StrikeAnalysis({
    required this.type,
    required this.qualityScore,
    required this.label,
    required this.feedback,
    required this.symmetryScore,
  });
}

class PressureAnalyzer {
  // ─── Analyse a single InsoleData frame ──────────────────
  static StrikeAnalysis analyze(InsoleData d) {
    final type = d.dominantStrike;

    // ── L/R symmetry (forefoot balance) ──────────────────
    final lrSum = d.forefootLeft + d.forefootRight;
    double symmetry = 100.0;
    if (lrSum > 0) {
      final bias = (d.forefootLeft - d.forefootRight).abs() / lrSum;
      symmetry = (1.0 - bias) * 100.0;
    }

    // ── Quality score heuristic ───────────────────────────
    // Ideal midfoot strike = forefoot sensors dominant, heel moderate.
    // Heel strike = heel >> forefoot (penalised for impact loading).
    // Toe strike = toe >> heel (mild penalty for over-pronation risk).
    double quality;
    String label;
    String feedback;

    switch (type) {
      case StrikeType.midfoot:
        quality = 80.0 + (symmetry * 0.2);
        label   = 'Midfoot Striker ✅';
        feedback= 'Great form! Maintain short, quick strides.';
        break;

      case StrikeType.heel:
        // Penalise proportional to how dominant heel is vs forefoot
        final heelRatio = d.heelNorm /
            (d.forefootLNorm + d.forefootRNorm + d.toeNorm + 0.001);
        quality  = (65.0 - heelRatio * 15.0).clamp(40.0, 65.0);
        label    = 'Heel Striker ⚠️';
        feedback = 'Try landing closer to your midfoot to reduce impact force.';
        break;

      case StrikeType.forefoot:
        quality  = 72.0 + (symmetry * 0.15);
        label    = 'Forefoot Striker';
        feedback = 'Good speed! Watch calf fatigue on long runs.';
        break;

      case StrikeType.unknown:
        quality  = 0.0;
        label    = 'No contact';
        feedback = 'Waiting for foot strike…';
        break;
    }

    return StrikeAnalysis(
      type:          type,
      qualityScore:  quality.clamp(0.0, 100.0),
      label:         label,
      feedback:      feedback,
      symmetryScore: symmetry.clamp(0.0, 100.0),
    );
  }

  // ─── Session-average score from history ─────────────────
  static double sessionScore(PressureHistory history) {
    if (history.isEmpty) return 0.0;
    final frames = history.frames
        .where((f) => f.totalPressure > 400)   // only active-contact frames
        .toList();
    if (frames.isEmpty) return 0.0;
    final sum = frames.map((f) => analyze(f).qualityScore).reduce((a, b) => a + b);
    return sum / frames.length;
  }

  // ─── Colour for a normalised pressure value (0–1) ───────
  // Green (low) → Yellow (medium) → Red (high)
  static (int r, int g, int b) pressureColor(double norm) {
    norm = norm.clamp(0.0, 1.0);
    if (norm < 0.5) {
      // Green → Yellow
      return (
        (norm * 2 * 255).round().clamp(0, 255),
        255,
        0,
      );
    } else {
      // Yellow → Red
      return (
        255,
        ((1.0 - (norm - 0.5) * 2) * 255).round().clamp(0, 255),
        0,
      );
    }
  }
}

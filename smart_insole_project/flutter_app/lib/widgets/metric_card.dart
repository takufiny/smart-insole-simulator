// ============================================================
// MetricCard — Reusable tile for a single running metric
// ============================================================

import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color? accentColor;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: accent, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold, color: accent)),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(unit,
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

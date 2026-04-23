import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../application/analytics/face_score_stats.dart' as stats;

/// Line chart of pass-rate as a function of threshold (0–1).
/// A vertical reference line marks the currently-selected threshold.
class PassRateCurveChart extends StatelessWidget {
  final List<double> scores; // pre-filtered, non-null face_scores
  final double threshold;

  const PassRateCurveChart({
    super.key,
    required this.scores,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('ไม่มีข้อมูล', style: TextStyle(color: Colors.white54))),
      );
    }

    // Build 101 points: t = 0.00, 0.01, …, 1.00
    final spots = List.generate(101, (i) {
      final t = i / 100.0;
      return FlSpot(t * 100, stats.passRateAtThreshold(scores, t) * 100);
    });

    final thresholdPct = threshold * 100;
    final passRateAtT =
        stats.passRateAtThreshold(scores, threshold) * 100;

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: 100,
          minY: 0,
          maxY: 100,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            horizontalInterval: 25,
            verticalInterval: 25,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.12),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.08),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 25,
                reservedSize: 24,
                getTitlesWidget: (v, _) => Text(
                  '${v.toInt()}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.white,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ],
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: thresholdPct,
                color: Colors.cyanAccent.withValues(alpha: 0.9),
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.only(bottom: 4, left: 4),
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  labelResolver: (_) =>
                      '${thresholdPct.toStringAsFixed(0)}% → pass ${passRateAtT.toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

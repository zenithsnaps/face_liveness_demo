import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../application/analytics/face_score_stats.dart' as stats;
import '../../providers/analytics_provider.dart';

/// Bar chart (20 buckets × 0.05 width) with vertical marker lines for
/// mean (yellow), median (orange), and threshold (cyan).
/// [yMode] switches y-axis between raw count and density (% of total).
class HistogramChart extends StatelessWidget {
  final List<double> scores;
  final double threshold;
  final double mean;
  final double median;
  final HistogramYMode yMode;

  const HistogramChart({
    super.key,
    required this.scores,
    required this.threshold,
    required this.mean,
    required this.median,
    this.yMode = HistogramYMode.count,
  });

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('ไม่มีข้อมูล', style: TextStyle(color: Colors.white54))),
      );
    }

    final isDensity = yMode == HistogramYMode.density;
    final counts = stats.histogramBuckets(scores, buckets: 20);
    final total = scores.length;
    final barValues = isDensity
        ? counts.map((c) => c / total * 100).toList() // percent 0–100
        : counts.map((c) => c.toDouble()).toList();
    final maxVal = barValues.reduce((a, b) => a > b ? a : b);

    final bars = List.generate(20, (i) {
      final fill = i * 5.0 >= threshold * 100
          ? Colors.greenAccent.withValues(alpha: 0.7)
          : Colors.white.withValues(alpha: 0.25);
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: barValues[i],
            color: fill,
            width: double.maxFinite,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
        barsSpace: 0,
      );
    });

    // Marker x-values in bar-index units (0–19)
    double scoreToBarX(double s) => (s * 20).clamp(0, 19.99);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: maxVal * 1.15,
          barGroups: bars,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: isDensity
                ? (maxVal / 4).ceilToDouble().clamp(1, double.maxFinite)
                : (maxVal / 4).ceilToDouble().clamp(1, double.maxFinite),
            getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.white.withValues(alpha: 0.12),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (v, _) {
                  final idx = v.toInt();
                  if (idx % 5 != 0) return const SizedBox.shrink();
                  return Text(
                    '${(idx * 5)}%',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 10),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (v, _) => Text(
                  isDensity ? '${v.toStringAsFixed(0)}%' : v.toInt().toString(),
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          barTouchData: BarTouchData(enabled: false),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: scoreToBarX(threshold),
                color: Colors.cyanAccent.withValues(alpha: 0.9),
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(bottom: 4, right: 4),
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 9),
                  labelResolver: (_) => 'T',
                ),
              ),
              VerticalLine(
                x: scoreToBarX(mean),
                color: Colors.yellowAccent.withValues(alpha: 0.85),
                strokeWidth: 1.5,
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.only(bottom: 4, left: 2),
                  style:
                      const TextStyle(color: Colors.yellowAccent, fontSize: 9),
                  labelResolver: (_) => 'μ',
                ),
              ),
              VerticalLine(
                x: scoreToBarX(median),
                color: Colors.orangeAccent.withValues(alpha: 0.85),
                strokeWidth: 1.5,
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(bottom: 14, right: 2),
                  style:
                      const TextStyle(color: Colors.orangeAccent, fontSize: 9),
                  labelResolver: (_) => 'Med',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

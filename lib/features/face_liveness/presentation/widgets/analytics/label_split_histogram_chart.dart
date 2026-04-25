import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../application/analytics/face_score_stats.dart' as stats;
import '../../providers/analytics_provider.dart';

/// Overlaid density histogram split by Live (green) / Spoof (red) label.
/// Y-axis shows density as % of each label's total count, making Live and
/// Spoof comparable even when sample sizes differ.
class LabelSplitHistogramChart extends StatelessWidget {
  final Map<TestCaseLabel, List<double>> scoresByLabel;
  final double threshold;

  const LabelSplitHistogramChart({
    super.key,
    required this.scoresByLabel,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    final liveScores = scoresByLabel[TestCaseLabel.live] ?? const [];
    final spoofScores = scoresByLabel[TestCaseLabel.spoof] ?? const [];
    final unlabeledCount =
        (scoresByLabel[TestCaseLabel.unlabeled] ?? const []).length;

    final hasLive = liveScores.isNotEmpty;
    final hasSpoof = spoofScores.isNotEmpty;

    if (!hasLive && !hasSpoof) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.label_outline,
                  color: Colors.white24, size: 32),
              const SizedBox(height: 8),
              const Text(
                'label test case เป็น Live / Spoof\nเพื่อดู chart นี้',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              if (unlabeledCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  '$unlabeledCount scores ยังไม่ได้ label',
                  style: const TextStyle(
                      color: Colors.white24, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      );
    }

    const buckets = 20;
    final liveDensity = hasLive
        ? stats.densityBuckets(liveScores, buckets: buckets)
        : List.filled(buckets, 0.0);
    final spoofDensity = hasSpoof
        ? stats.densityBuckets(spoofScores, buckets: buckets)
        : List.filled(buckets, 0.0);

    // Scale to percent for readable y-axis labels
    final livePct = liveDensity.map((v) => v * 100).toList();
    final spoofPct = spoofDensity.map((v) => v * 100).toList();

    final maxVal = [...livePct, ...spoofPct].reduce((a, b) => a > b ? a : b);

    // Two rods per group, side by side
    final bars = List.generate(buckets, (i) {
      return BarChartGroupData(
        x: i,
        barsSpace: 1,
        barRods: [
          if (hasLive)
            BarChartRodData(
              toY: livePct[i],
              color: Colors.greenAccent.withValues(alpha: 0.75),
              width: hasSpoof ? 5 : 10,
              borderRadius: BorderRadius.circular(1),
            ),
          if (hasSpoof)
            BarChartRodData(
              toY: spoofPct[i],
              color: Colors.redAccent.withValues(alpha: 0.75),
              width: hasLive ? 5 : 10,
              borderRadius: BorderRadius.circular(1),
            ),
        ],
      );
    });

    double scoreToBarX(double s) => (s * buckets).clamp(0, buckets - 0.01);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Wrap(
          spacing: 12,
          children: [
            if (hasLive)
              _LegendDot(
                  color: Colors.greenAccent,
                  label: 'Live (n=${liveScores.length})'),
            if (hasSpoof)
              _LegendDot(
                  color: Colors.redAccent,
                  label: 'Spoof (n=${spoofScores.length})'),
            if (unlabeledCount > 0)
              Text(
                '$unlabeledCount unlabeled ไม่แสดง',
                style: const TextStyle(
                    color: Colors.white24, fontSize: 10),
              ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceBetween,
              maxY: maxVal * 1.2,
              barGroups: bars,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval:
                    (maxVal / 4).ceilToDouble().clamp(1, double.maxFinite),
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
                        '${idx * 5}%',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 10),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toStringAsFixed(0)}%',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 10),
                    ),
                  ),
                ),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
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
                      padding:
                          const EdgeInsets.only(bottom: 4, right: 4),
                      style: const TextStyle(
                          color: Colors.cyanAccent, fontSize: 9),
                      labelResolver: (_) => 'T',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      );
}

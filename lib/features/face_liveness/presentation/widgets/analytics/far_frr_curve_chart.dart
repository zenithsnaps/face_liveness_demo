import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../application/analytics/face_score_stats.dart' as stats;

/// Line chart showing FAR (False Accept Rate) and FRR (False Reject Rate)
/// as a function of threshold, with the Equal Error Rate (EER) marked.
///
/// FAR = fraction of spoof scores ≥ threshold (spoofs incorrectly accepted).
/// FRR = fraction of live scores < threshold (live faces incorrectly rejected).
/// EER = threshold where |FAR - FRR| is minimised — a natural balance point.
class FarFrrCurveChart extends StatelessWidget {
  final List<double> liveScores;
  final List<double> spoofScores;
  final double threshold;

  const FarFrrCurveChart({
    super.key,
    required this.liveScores,
    required this.spoofScores,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    if (liveScores.isEmpty || spoofScores.isEmpty) {
      final missing = <String>[];
      if (liveScores.isEmpty) missing.add('Live');
      if (spoofScores.isEmpty) missing.add('Spoof');
      return SizedBox(
        height: 160,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.label_outline,
                  color: Colors.white24, size: 32),
              const SizedBox(height: 8),
              Text(
                'ต้องการข้อมูล ${missing.join(' และ ')}\n'
                'label test case เป็น Live / Spoof เพื่อดู chart นี้',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final curve = stats.farFrrCurve(liveScores, spoofScores, points: 101);
    final eer = stats.equalErrorRate(curve);

    // Convert to fl_chart spots (x = threshold × 100, y = rate × 100)
    final frrSpots = curve
        .map((p) => FlSpot(p.t * 100, p.frr * 100))
        .toList();
    final farSpots = curve
        .map((p) => FlSpot(p.t * 100, p.far * 100))
        .toList();

    final thresholdPct = threshold * 100;
    final atT = stats.farFrrAt(liveScores, spoofScores, threshold);

    final eerLabel = eer != null
        ? 'EER ${(eer.rate * 100).toStringAsFixed(1)}%  @  T=${(eer.threshold * 100).toStringAsFixed(0)}%'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Wrap(
          spacing: 12,
          children: [
            _LegendLine(color: Colors.redAccent, label: 'FRR (live rejected)'),
            _LegendLine(color: Colors.blueAccent, label: 'FAR (spoof accepted)'),
            if (eer != null)
              _LegendDot(
                  color: Colors.amberAccent, label: eerLabel!),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
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
                  axisNameWidget: const Text('Rate',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  axisNameSize: 16,
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 25,
                    reservedSize: 36,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}%',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: const Text('Threshold',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
                  axisNameSize: 16,
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 25,
                    reservedSize: 22,
                    getTitlesWidget: (v, _) => Text(
                      '${v.toInt()}%',
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
              lineBarsData: [
                // FRR line (red)
                LineChartBarData(
                  spots: frrSpots,
                  isCurved: true,
                  color: Colors.redAccent,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                // FAR line (blue)
                LineChartBarData(
                  spots: farSpots,
                  isCurved: true,
                  color: Colors.blueAccent,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                // EER point highlighted as a single dot
                if (eer != null)
                  LineChartBarData(
                    spots: [FlSpot(eer.threshold * 100, eer.rate * 100)],
                    color: Colors.amberAccent,
                    barWidth: 0,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, idx) =>
                          FlDotCirclePainter(
                        radius: 5,
                        color: Colors.amberAccent,
                        strokeWidth: 1.5,
                        strokeColor: Colors.black87,
                      ),
                    ),
                  ),
              ],
              extraLinesData: ExtraLinesData(
                verticalLines: [
                  // Current threshold marker
                  VerticalLine(
                    x: thresholdPct,
                    color: Colors.cyanAccent.withValues(alpha: 0.9),
                    strokeWidth: 1.5,
                    dashArray: [6, 4],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topLeft,
                      padding:
                          const EdgeInsets.only(bottom: 4, left: 4),
                      style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 9,
                          fontWeight: FontWeight.w600),
                      labelResolver: (_) =>
                          'T  FRR=${(atT.frr * 100).toStringAsFixed(1)}%'
                          '  FAR=${(atT.far * 100).toStringAsFixed(1)}%',
                    ),
                  ),
                  // EER vertical marker
                  if (eer != null)
                    VerticalLine(
                      x: eer.threshold * 100,
                      color: Colors.amberAccent.withValues(alpha: 0.6),
                      strokeWidth: 1,
                      dashArray: [3, 4],
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

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendLine({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 16, height: 2, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11)),
        ],
      );
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
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11)),
        ],
      );
}

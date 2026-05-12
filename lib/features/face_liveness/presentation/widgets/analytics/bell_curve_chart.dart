import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../providers/analytics_provider.dart';

/// Smooth Gaussian bell curve fitted to the face_score distribution
/// (mean = μ from data, σ = sample stddev).
/// Supports pinch-to-zoom and double-tap to reset zoom.
class BellCurveChart extends StatefulWidget {
  final List<double> scores;
  final double threshold;
  final double mean;
  final double median;
  final double? currentScore;
  final HistogramYMode yMode;

  const BellCurveChart({
    super.key,
    required this.scores,
    required this.threshold,
    required this.mean,
    required this.median,
    this.currentScore,
    this.yMode = HistogramYMode.density,
  });

  @override
  State<BellCurveChart> createState() => _BellCurveChartState();
}

class _BellCurveChartState extends State<BellCurveChart> {
  final _transformController = TransformationController();
  bool _isZoomed = false;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    setState(() {
      _transformController.value = Matrix4.identity();
      _isZoomed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.scores.length < 2) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('ข้อมูลไม่พอสำหรับ bell curve',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }

    final mean = widget.mean;
    final n = widget.scores.length.toDouble();
    var variance = 0.0;
    for (final s in widget.scores) {
      variance += (s - mean) * (s - mean);
    }
    variance /= (n - 1);
    var sigma = math.sqrt(variance);
    if (sigma < 0.01) sigma = 0.01;

    final isDensity = widget.yMode == HistogramYMode.density;
    const bucketWidth = 0.05;
    final scale = isDensity ? bucketWidth * 100 : n * bucketWidth;

    const points = 201;
    final spots = <FlSpot>[];
    var maxY = 0.0;
    final twoSigmaSq = 2 * sigma * sigma;
    final norm = 1 / (sigma * math.sqrt(2 * math.pi));
    for (var i = 0; i < points; i++) {
      final x = i / (points - 1);
      final dx = x - mean;
      final pdf = norm * math.exp(-(dx * dx) / twoSigmaSq);
      final y = pdf * scale;
      spots.add(FlSpot(x, y));
      if (y > maxY) maxY = y;
    }

    final curve = LineChartBarData(
      spots: spots,
      isCurved: false,
      color: Colors.cyanAccent.withValues(alpha: 0.85),
      barWidth: 2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: Colors.cyanAccent.withValues(alpha: 0.16),
      ),
    );

    final chart = SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: 1,
          minY: 0,
          maxY: maxY * 1.18,
          lineBarsData: [curve],
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
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
                interval: 0.25,
                getTitlesWidget: (v, _) => Text(
                  '${(v * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (v, _) {
                  if (v < 0) return const SizedBox.shrink();
                  return Text(
                    isDensity
                        ? '${v.toStringAsFixed(1)}%'
                        : v.toStringAsFixed(0),
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: const LineTouchData(enabled: false),
          extraLinesData: ExtraLinesData(
            verticalLines: [
              VerticalLine(
                x: widget.threshold.clamp(0.0, 1.0),
                color: Colors.cyanAccent.withValues(alpha: 0.9),
                strokeWidth: 1.5,
                dashArray: [6, 4],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(bottom: 4, right: 4),
                  style:
                      const TextStyle(color: Colors.cyanAccent, fontSize: 9),
                  labelResolver: (_) => 'T',
                ),
              ),
              VerticalLine(
                x: mean.clamp(0.0, 1.0),
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
                x: widget.median.clamp(0.0, 1.0),
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
              if (widget.currentScore != null)
                VerticalLine(
                  x: widget.currentScore!.clamp(0.0, 1.0),
                  color: const Color(0xFFFF4FD8),
                  strokeWidth: 2.5,
                  label: VerticalLineLabel(
                    show: true,
                    alignment: Alignment.topLeft,
                    padding: const EdgeInsets.only(bottom: 26, left: 2),
                    style: const TextStyle(
                      color: Color(0xFFFF4FD8),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                    labelResolver: (_) =>
                        'เคสนี้ ${(widget.currentScore!.clamp(0.0, 1.0) * 100).toStringAsFixed(1)}%',
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onDoubleTap: _resetZoom,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _transformController,
              // Allow panning only when zoomed (boundaryMargin adds slack).
              boundaryMargin: const EdgeInsets.symmetric(horizontal: 60),
              minScale: 1.0,
              maxScale: 12.0,
              onInteractionEnd: (_) {
                final zoomed =
                    _transformController.value.getMaxScaleOnAxis() > 1.05;
                if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
              },
              child: chart,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: GestureDetector(
            onTap: _isZoomed ? _resetZoom : null,
            child: Text(
              _isZoomed ? 'double-tap หรือแตะที่นี่เพื่อ reset' : 'pinch เพื่อ zoom',
              style: TextStyle(
                color: _isZoomed
                    ? Colors.cyanAccent.withValues(alpha: 0.6)
                    : Colors.white24,
                fontSize: 9,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

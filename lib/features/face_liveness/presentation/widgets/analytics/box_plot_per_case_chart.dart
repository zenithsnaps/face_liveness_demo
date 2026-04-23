import 'package:flutter/material.dart';

import '../../../application/analytics/face_score_stats.dart' as stats;

/// Custom-painted box-plot chart, one column per test_case group.
/// Threshold is drawn as a horizontal cyan dashed line.
class BoxPlotPerCaseChart extends StatelessWidget {
  /// Map from test_case label (or "ทั้งหมด") to list of face_scores.
  final Map<String, List<double>> groups;
  final double threshold;
  final double height;

  const BoxPlotPerCaseChart({
    super.key,
    required this.groups,
    required this.threshold,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty ||
        groups.values.every((xs) => xs.isEmpty)) {
      return SizedBox(
        height: height,
        child: const Center(
            child: Text('ไม่มีข้อมูล',
                style: TextStyle(color: Colors.white54))),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BoxPlotPainter(groups: groups, threshold: threshold),
        size: Size.infinite,
      ),
    );
  }
}

class _BoxPlotPainter extends CustomPainter {
  final Map<String, List<double>> groups;
  final double threshold;

  _BoxPlotPainter({required this.groups, required this.threshold});

  @override
  void paint(Canvas canvas, Size size) {
    final entries =
        groups.entries.where((e) => e.value.isNotEmpty).toList();
    if (entries.isEmpty) return;

    const labelHeight = 28.0;
    final chartH = size.height - labelHeight;
    final colW = size.width / entries.length;

    double yFor(double v) => chartH - v.clamp(0.0, 1.0) * chartH;

    // Grid at 25/50/75/100%
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final v in [0.25, 0.5, 0.75, 1.0]) {
      final y = yFor(v);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Threshold line
    final threshY = yFor(threshold);
    final tPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, threshY),
        Offset((x + 6).clamp(0, size.width), threshY),
        tPaint,
      );
      x += 10;
    }

    for (var i = 0; i < entries.length; i++) {
      final cx = colW * i + colW / 2;
      final sorted = [...entries[i].value]..sort();
      final s = stats.summarize(sorted);

      final boxLeft = cx - colW * 0.22;
      final boxRight = cx + colW * 0.22;

      // Whisker
      final whiskerPaint = Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(cx, yFor(s.min)), Offset(cx, yFor(s.max)),
          whiskerPaint);
      canvas.drawLine(Offset(cx - 6, yFor(s.min)),
          Offset(cx + 6, yFor(s.min)), whiskerPaint);
      canvas.drawLine(Offset(cx - 6, yFor(s.max)),
          Offset(cx + 6, yFor(s.max)), whiskerPaint);

      // Box
      final boxPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill;
      final boxRect = Rect.fromLTRB(
          boxLeft, yFor(s.q3), boxRight, yFor(s.q1));
      canvas.drawRect(boxRect, boxPaint);
      final boxBorderPaint = Paint()
        ..color = Colors.white54
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(boxRect, boxBorderPaint);

      // Median line
      final medPaint = Paint()
        ..color = Colors.orangeAccent
        ..strokeWidth = 2;
      canvas.drawLine(
          Offset(boxLeft, yFor(s.median)),
          Offset(boxRight, yFor(s.median)),
          medPaint);

      // Mean dot
      canvas.drawCircle(
          Offset(cx, yFor(s.mean)),
          4,
          Paint()..color = Colors.yellowAccent);

      // Label
      final label = entries[i].key;
      final tp = TextPainter(
        text: TextSpan(
          text: label.length > 12 ? '${label.substring(0, 10)}…' : label,
          style: const TextStyle(color: Colors.white70, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset(cx - tp.width / 2, chartH + (labelHeight - tp.height) / 2));
    }

    // Legend
    void dot(Color c, double lx, double ly) =>
        canvas.drawCircle(Offset(lx, ly), 4, Paint()..color = c);
    void lineMark(Color c, double lx, double ly) =>
        canvas.drawLine(
            Offset(lx - 8, ly),
            Offset(lx + 8, ly),
            Paint()
              ..color = c
              ..strokeWidth = 2);

    const legendTop = 6.0;
    dot(Colors.yellowAccent, 6, legendTop);
    _drawLegendText(canvas, 'mean', 14, legendTop - 5);
    lineMark(Colors.orangeAccent, 56, legendTop);
    _drawLegendText(canvas, 'median', 68, legendTop - 5);
  }

  void _drawLegendText(Canvas canvas, String text, double x, double y) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white54, fontSize: 9),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant _BoxPlotPainter old) =>
      old.groups != groups || old.threshold != threshold;
}

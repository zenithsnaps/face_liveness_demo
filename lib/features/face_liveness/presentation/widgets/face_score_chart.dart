import 'package:flutter/material.dart';

/// Realtime line chart of MediaPipe face detection scores vs. the post-capture
/// pass threshold. Most-recent sample is on the right edge.
class FaceScoreChart extends StatelessWidget {
  final List<double?> samples;
  final double threshold;
  final double height;

  const FaceScoreChart({
    super.key,
    required this.samples,
    required this.threshold,
    this.height = 72,
  });

  @override
  Widget build(BuildContext context) {
    final latest = samples.isNotEmpty ? samples.last : null;
    final passing = latest != null && latest >= threshold;
    final latestText = latest != null
        ? '${(latest * 100).toStringAsFixed(0)}%'
        : '—';
    final thresholdText = '${(threshold * 100).toStringAsFixed(0)}%';
    final latestColor = passing ? Colors.greenAccent : Colors.orangeAccent;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Face score (live)',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: latestText,
                    style: TextStyle(
                      color: latestColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(
                    text: '  /  $thresholdText',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: _ChartPainter(
                samples: samples,
                threshold: threshold,
                maxSamples: 60,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<double?> samples;
  final double threshold;
  final int maxSamples;

  _ChartPainter({
    required this.samples,
    required this.threshold,
    required this.maxSamples,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Y mapping: 0% at bottom, 100% at top.
    double yFor(double v) => h - (v.clamp(0.0, 1.0) * h);

    // Grid: 25/50/75%
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final v in [0.25, 0.5, 0.75]) {
      final y = yFor(v);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Threshold line
    final thresholdY = yFor(threshold);
    final thresholdPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.85)
      ..strokeWidth = 1.5;
    final dashWidth = 6.0;
    final dashGap = 4.0;
    double x = 0;
    while (x < w) {
      canvas.drawLine(
        Offset(x, thresholdY),
        Offset((x + dashWidth).clamp(0.0, w), thresholdY),
        thresholdPaint,
      );
      x += dashWidth + dashGap;
    }

    if (samples.isEmpty) return;

    // X mapping: oldest sample at left, newest at right. Reserve maxSamples
    // worth of slots so a half-full buffer doesn't stretch across the whole
    // width — it should "fill in" from the right.
    final stride = w / (maxSamples - 1);
    final startIndex = maxSamples - samples.length;

    final linePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = Colors.white;
    final missDotPaint = Paint()..color = Colors.redAccent.withValues(alpha: 0.85);

    Offset? prev;
    for (var i = 0; i < samples.length; i++) {
      final px = (startIndex + i) * stride;
      final s = samples[i];
      if (s == null) {
        // Mark "no face" with a small red dot at the bottom.
        canvas.drawCircle(Offset(px, h - 1), 1.6, missDotPaint);
        prev = null;
        continue;
      }
      final point = Offset(px, yFor(s));
      if (prev != null) {
        canvas.drawLine(prev, point, linePaint);
      }
      prev = point;
    }

    // Highlight the most recent sample.
    final last = samples.last;
    if (last != null) {
      final lastPoint = Offset(w, yFor(last));
      canvas.drawCircle(lastPoint, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) =>
      old.samples != samples || old.threshold != threshold;
}

import 'package:flutter/material.dart';

enum OvalStatus { neutral, working, success, failure }

class FaceOvalOverlay extends StatelessWidget {
  final OvalStatus status;

  const FaceOvalOverlay({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _OvalPainter(status: status),
    );
  }
}

class _OvalPainter extends CustomPainter {
  final OvalStatus status;
  _OvalPainter({required this.status});

  @override
  void paint(Canvas canvas, Size size) {
    final ovalRect = computeOvalRect(size);

    // Dim backdrop with oval hole.
    final backdrop = Path()..addRect(Offset.zero & size);
    final hole = Path()..addOval(ovalRect);
    final withHole = Path.combine(PathOperation.difference, backdrop, hole);
    canvas.drawPath(
      withHole,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // Oval outline.
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = _statusColor(status);
    canvas.drawOval(ovalRect, outline);
  }

  Color _statusColor(OvalStatus s) => switch (s) {
        OvalStatus.neutral => Colors.white,
        OvalStatus.working => Colors.white,
        OvalStatus.success => const Color(0xFF34C759),
        OvalStatus.failure => const Color(0xFFFF3B30),
      };

  @override
  bool shouldRepaint(_OvalPainter oldDelegate) => oldDelegate.status != status;
}

/// Compute the oval-guide rect in widget (screen) coordinates. Exposed for the
/// liveness screen so we can convert frame-space bboxes back and forth.
Rect computeOvalRect(Size size) {
  final w = size.width * 0.7;
  final h = size.height * 0.55;
  final left = (size.width - w) / 2;
  final top = (size.height - h) / 2 - size.height * 0.05;
  return Rect.fromLTWH(left, top, w, h);
}

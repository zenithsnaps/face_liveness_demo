import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'point2d.dart';

@immutable
class Rect2D {
  final double left;
  final double top;
  final double width;
  final double height;

  const Rect2D({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  })  : assert(width >= 0, 'width must be non-negative'),
        assert(height >= 0, 'height must be non-negative');

  const Rect2D.fromLTWH(this.left, this.top, this.width, this.height);

  factory Rect2D.fromLTRB(double left, double top, double right, double bottom) {
    return Rect2D.fromLTWH(left, top, right - left, bottom - top);
  }

  double get right => left + width;
  double get bottom => top + height;
  double get area => width * height;
  Point2D get center => Point2D(left + width / 2, top + height / 2);

  bool contains(Point2D p) =>
      p.x >= left && p.x <= right && p.y >= top && p.y <= bottom;

  /// Expand the rect by [factor] on all sides (0.15 → 15% larger in each direction).
  Rect2D expanded(double factor) {
    final dx = width * factor;
    final dy = height * factor;
    return Rect2D.fromLTWH(left - dx, top - dy, width + 2 * dx, height + 2 * dy);
  }

  /// Intersection area with [other]. Returns 0 if disjoint.
  double intersectArea(Rect2D other) {
    final l = math.max(left, other.left);
    final t = math.max(top, other.top);
    final r = math.min(right, other.right);
    final b = math.min(bottom, other.bottom);
    if (r <= l || b <= t) return 0;
    return (r - l) * (b - t);
  }

  /// IoU in [0, 1].
  double iou(Rect2D other) {
    final inter = intersectArea(other);
    if (inter == 0) return 0;
    final union = area + other.area - inter;
    if (union == 0) return 0;
    return inter / union;
  }

  /// Fraction of [other]'s area that overlaps with this rect.
  double overlapFractionOf(Rect2D other) {
    if (other.area == 0) return 0;
    return intersectArea(other) / other.area;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Rect2D &&
          other.left == left &&
          other.top == top &&
          other.width == width &&
          other.height == height);

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'Rect2D(l=$left, t=$top, w=$width, h=$height)';
}

import 'dart:math' as math;

import 'package:meta/meta.dart';

@immutable
class Point2D {
  final double x;
  final double y;

  const Point2D(this.x, this.y);

  Point2D translate(double dx, double dy) => Point2D(x + dx, y + dy);

  double distanceTo(Point2D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Point2D && other.x == x && other.y == y);

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2D($x, $y)';
}

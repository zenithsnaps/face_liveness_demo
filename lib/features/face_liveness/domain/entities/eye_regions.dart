import 'package:meta/meta.dart';

import '../value_objects/point2d.dart';
import '../value_objects/rect2d.dart';

@immutable
class EyeRegions {
  /// Contour points (~16) around the left eye in image-pixel coordinates.
  final List<Point2D> leftEye;

  /// Contour points (~16) around the right eye in image-pixel coordinates.
  final List<Point2D> rightEye;

  /// Left cheek landmark position (reference region for contrast computation).
  final Point2D? leftCheek;

  /// Right cheek landmark position (reference region for contrast computation).
  final Point2D? rightCheek;

  /// Face bounding box — used to size the cheek reference patch.
  final Rect2D faceBox;

  const EyeRegions({
    required this.leftEye,
    required this.rightEye,
    required this.faceBox,
    this.leftCheek,
    this.rightCheek,
  });
}

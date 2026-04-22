import 'package:meta/meta.dart';

import '../value_objects/confidence.dart';
import '../value_objects/point2d.dart';

/// A single detected hand's 21-landmark skeleton in frame pixel space.
///
/// MediaPipe Hand Landmarker returns landmarks in a fixed order:
/// 0: wrist, 1-4: thumb, 5-8: index, 9-12: middle, 13-16: ring, 17-20: pinky.
/// Indices 4, 8, 12, 16, 20 are the five fingertips.
@immutable
class HandSnapshot {
  /// 21 landmarks in the canonical MediaPipe order, already converted to
  /// frame pixel coordinates by the infrastructure layer.
  final List<Point2D> landmarks;
  final Confidence confidence;
  final Handedness handedness;

  const HandSnapshot({
    required this.landmarks,
    required this.confidence,
    required this.handedness,
  }) : assert(landmarks.length == 21,
            'MediaPipe hand landmarks must be 21 points');

  Point2D get wrist => landmarks[0];
  Point2D get thumbTip => landmarks[4];
  Point2D get indexTip => landmarks[8];
  Point2D get middleTip => landmarks[12];
  Point2D get ringTip => landmarks[16];
  Point2D get pinkyTip => landmarks[20];
}

enum Handedness { left, right, unknown }

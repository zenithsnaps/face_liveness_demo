import 'package:meta/meta.dart';

import '../value_objects/confidence.dart';
import '../value_objects/euler_angles.dart';
import '../value_objects/point2d.dart';
import '../value_objects/rect2d.dart';

/// Analyzer-agnostic snapshot of a detected face in a single frame.
@immutable
class FaceSnapshot {
  final Rect2D boundingBox;
  final EulerAngles headPose;
  final Confidence smilingProbability;
  final Confidence leftEyeOpenProbability;
  final Confidence rightEyeOpenProbability;

  /// Key landmark positions keyed by role (nose, leftEye, rightEye, mouth, etc.)
  /// Coordinates are in the same pixel space as [boundingBox].
  final Map<FaceLandmarkType, Point2D> landmarks;

  /// Per-landmark visibility scores from occlusion-aware models (e.g. MediaPipe
  /// Face Landmarker). ML Kit does not expose these — it will leave this empty.
  final Map<FaceLandmarkType, Confidence> landmarkVisibility;

  const FaceSnapshot({
    required this.boundingBox,
    required this.headPose,
    required this.smilingProbability,
    required this.leftEyeOpenProbability,
    required this.rightEyeOpenProbability,
    this.landmarks = const {},
    this.landmarkVisibility = const {},
  });
}

enum FaceLandmarkType {
  leftEye,
  rightEye,
  noseBase,
  mouthLeft,
  mouthRight,
  mouthBottom,
  leftCheek,
  rightCheek,
  leftEar,
  rightEar,
}

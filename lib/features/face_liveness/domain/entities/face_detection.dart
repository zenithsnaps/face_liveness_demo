import '../../domain/value_objects/rect2d.dart';
import '../../domain/value_objects/confidence.dart';

/// A single face detection result from the MediaPipe Face Detector.
///
/// Distinct from [FaceSnapshot] (which carries landmarks + classifications
/// from ML Kit) — this is a lightweight bbox + score only.
class FaceDetection {
  const FaceDetection({required this.boundingBox, required this.score});

  final Rect2D boundingBox;
  final Confidence score;
}

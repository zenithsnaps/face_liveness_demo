import '../../../../core/result.dart';
import '../entities/frame_data.dart';
import '../entities/glasses_evidence.dart';
import '../failures/liveness_failure.dart';
import '../value_objects/rect2d.dart';

/// Classifies whether the face in a frame is wearing sunglasses, using an
/// on-device TFLite model.
///
/// Unlike [EyeContourAnalyzer] / pixel-statistic approaches, this asks a
/// trained classifier "is this sunglasses?" rather than "is this region
/// dark?", so it is robust to reflective / matte / tinted lenses and to skin
/// tone. See `docs/glasses_classifier_compare.jpg` for the comparison.
abstract class GlassesClassifierAnalyzer {
  /// Run the classifier on [frame] (RGBA8888, already upright).
  ///
  /// When [faceBox] is provided the region is cropped (expanded by a margin)
  /// before inference; when null the whole frame is used. Returns [Err] on
  /// model/IO failure so the caller can decide whether to skip or fail.
  Future<Result<GlassesEvidence, AnalyzerError>> analyze(
    FrameData frame, {
    Rect2D? faceBox,
  });

  Future<void> dispose();
}

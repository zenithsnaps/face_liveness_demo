import '../../domain/entities/frame_data.dart';
import '../../domain/entities/glasses_evidence.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/glasses_classifier_analyzer.dart';
import '../../domain/value_objects/rect2d.dart';
import '../../../../core/result.dart';

/// Post-capture check: fail when the captured face is wearing sunglasses,
/// using the on-device TFLite classifier.
///
/// Returns [Ok] with the [GlassesEvidence] either way — the caller inspects
/// [GlassesEvidence.isWearingSunglasses] to decide whether to block — and
/// [Err] only when the model itself failed (so the caller can skip rather
/// than block a clean capture on an analyzer hiccup, mirroring how
/// [CheckNoEyeOcclusion] is wired in `validate_capture.dart`).
class CheckNoSunglasses {
  final GlassesClassifierAnalyzer analyzer;

  const CheckNoSunglasses(this.analyzer);

  Future<Result<GlassesEvidence, AnalyzerError>> call({
    required FrameData frame,
    Rect2D? faceBox,
  }) =>
      analyzer.analyze(frame, faceBox: faceBox);
}

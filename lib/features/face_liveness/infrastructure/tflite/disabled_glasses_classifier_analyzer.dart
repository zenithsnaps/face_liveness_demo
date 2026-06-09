import '../../../../core/result.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/glasses_evidence.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/glasses_classifier_analyzer.dart';
import '../../domain/value_objects/rect2d.dart';

/// No-op [GlassesClassifierAnalyzer] used until on-device inference is wired
/// through MediaPipe.
///
/// WHY THIS EXISTS: the obvious implementation (the `tflite_flutter` plugin,
/// preserved at `tools/glasses_export/tflite_glasses_classifier_analyzer.dart.reference`)
/// links its own `TensorFlowLiteC` framework, which collides with the copy of
/// TensorFlow Lite that `MediaPipeTasksCommon` statically embeds — 41 duplicate
/// symbols, the iOS link fails. MediaPipe does not export the TFLite C API, so
/// FFI-reuse is impossible too. On-device inference must therefore run through
/// MediaPipe's own runtime (Tasks `ImageClassifier`) via the existing platform
/// channel; until that native path lands this analyzer reports "unavailable"
/// so callers skip the check rather than block a capture.
class DisabledGlassesClassifierAnalyzer implements GlassesClassifierAnalyzer {
  const DisabledGlassesClassifierAnalyzer();

  @override
  Future<Result<GlassesEvidence, AnalyzerError>> analyze(
    FrameData frame, {
    Rect2D? faceBox,
  }) async =>
      const Err(AnalyzerError('glasses classifier unavailable (native '
          'MediaPipe inference not yet wired)'));

  @override
  Future<void> dispose() async {}
}

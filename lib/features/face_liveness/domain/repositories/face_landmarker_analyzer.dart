import '../../../../core/result.dart';
import '../entities/face_snapshot.dart';
import '../entities/frame_data.dart';
import '../failures/liveness_failure.dart';
import '../value_objects/confidence.dart';

/// Returns per-landmark visibility scores from the 478-point face mesh for a
/// captured frame. Used exclusively for post-capture occlusion checks.
abstract class FaceLandmarkerAnalyzer {
  Future<Result<Map<FaceLandmarkType, Confidence>, AnalyzerError>> analyze(
    FrameData frame,
  );
}

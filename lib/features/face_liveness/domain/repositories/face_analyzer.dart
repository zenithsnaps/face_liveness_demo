import '../../../../core/result.dart';
import '../entities/face_snapshot.dart';
import '../entities/frame_data.dart';
import '../failures/liveness_failure.dart';

/// Analyzes a frame for ONE face.
///
/// Contract:
/// - Returns `Ok(null)` when no face is detected.
/// - Returns `Ok(FaceSnapshot)` when exactly one face is detected.
/// - Returns `Err(AnalyzerError)` when more than one face is detected,
///   or when the underlying SDK fails.
abstract class FaceAnalyzer {
  Future<Result<FaceSnapshot?, AnalyzerError>> analyze(FrameData frame);
  Future<void> dispose();
}

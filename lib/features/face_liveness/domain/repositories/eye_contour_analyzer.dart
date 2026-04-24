import '../../../../core/result.dart';
import '../entities/eye_regions.dart';
import '../entities/frame_data.dart';
import '../failures/liveness_failure.dart';

abstract class EyeContourAnalyzer {
  /// Detect one face in [frame] (RGBA8888, already upright) and return eye
  /// contour polygons + cheek landmarks.
  /// Returns [Ok(null)] when no face is found; [Err] on SDK failure.
  Future<Result<EyeRegions?, AnalyzerError>> analyze(FrameData frame);
  Future<void> dispose();
}

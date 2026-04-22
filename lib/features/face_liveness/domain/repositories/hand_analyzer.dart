import '../../../../core/result.dart';
import '../entities/frame_data.dart';
import '../entities/hand_snapshot.dart';
import '../failures/liveness_failure.dart';

/// Detects up to `AppConstants.maxHands` hands in a frame.
///
/// Returns an empty list when no hands are visible.
abstract class HandAnalyzer {
  Future<Result<List<HandSnapshot>, AnalyzerError>> analyze(FrameData frame);
  Future<void> initialize();
  Future<void> dispose();
}

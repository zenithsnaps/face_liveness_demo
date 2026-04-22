import '../../../../core/result.dart';
import '../entities/frame_data.dart';
import '../entities/object_snapshot.dart';
import '../failures/liveness_failure.dart';

/// Detects generic objects (phone, cup, card, book, ...) in a frame.
abstract class ObjectAnalyzer {
  Future<Result<List<ObjectSnapshot>, AnalyzerError>> analyze(FrameData frame);
  Future<void> initialize();
  Future<void> dispose();
}

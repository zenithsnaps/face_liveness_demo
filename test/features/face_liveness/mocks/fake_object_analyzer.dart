import 'package:face_liveness_demo/core/result.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/object_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/repositories/object_analyzer.dart';

class FakeObjectAnalyzer implements ObjectAnalyzer {
  Result<List<ObjectSnapshot>, AnalyzerError> nextResult = const Ok([]);
  int analyzeCalls = 0;

  @override
  Future<Result<List<ObjectSnapshot>, AnalyzerError>> analyze(FrameData frame) async {
    analyzeCalls++;
    return nextResult;
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

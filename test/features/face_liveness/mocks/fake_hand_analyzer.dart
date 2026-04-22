import 'package:face_liveness_demo/core/result.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/hand_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/repositories/hand_analyzer.dart';

class FakeHandAnalyzer implements HandAnalyzer {
  Result<List<HandSnapshot>, AnalyzerError> nextResult = const Ok([]);
  int analyzeCalls = 0;
  int initializeCalls = 0;

  @override
  Future<Result<List<HandSnapshot>, AnalyzerError>> analyze(FrameData frame) async {
    analyzeCalls++;
    return nextResult;
  }

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> dispose() async {}
}

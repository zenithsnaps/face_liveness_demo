import 'package:face_liveness_demo/core/result.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/face_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/repositories/face_analyzer.dart';

class FakeFaceAnalyzer implements FaceAnalyzer {
  Result<FaceSnapshot?, AnalyzerError> nextResult = const Ok(null);
  int analyzeCalls = 0;

  @override
  Future<Result<FaceSnapshot?, AnalyzerError>> analyze(FrameData frame) async {
    analyzeCalls++;
    return nextResult;
  }

  @override
  Future<void> dispose() async {}
}

import 'package:face_liveness_demo/core/result.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/face_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/repositories/face_landmarker_analyzer.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/confidence.dart';

class FakeFaceLandmarkerAnalyzer implements FaceLandmarkerAnalyzer {
  Result<Map<FaceLandmarkType, Confidence>, AnalyzerError> nextResult =
      const Ok({});
  int analyzeCalls = 0;

  @override
  Future<Result<Map<FaceLandmarkType, Confidence>, AnalyzerError>> analyze(
    FrameData frame,
  ) async {
    analyzeCalls++;
    return nextResult;
  }
}

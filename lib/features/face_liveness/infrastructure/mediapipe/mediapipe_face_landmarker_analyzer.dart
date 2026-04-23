import '../../../../core/result.dart';
import '../../domain/entities/face_snapshot.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/face_landmarker_analyzer.dart';
import '../../domain/value_objects/confidence.dart';
import '../platform_channels/mediapipe_channel.dart';

/// Runs MediaPipe FaceLandmarker on a captured frame and extracts per-landmark
/// visibility scores for the mouth and nose region.
///
/// Used exclusively for post-capture occlusion validation — not in real-time.
///
/// Canonical 478-point face mesh indices used (MediaPipe standard):
///   1   → nose tip      (noseBase)
///   61  → left mouth corner   (mouthLeft)
///   291 → right mouth corner  (mouthRight)
///   17  → lower lip bottom    (mouthBottom)
class MediaPipeFaceLandmarkerAnalyzer implements FaceLandmarkerAnalyzer {
  final MediaPipeChannel _channel;

  MediaPipeFaceLandmarkerAnalyzer(this._channel);

  static const _indexMap = {
    FaceLandmarkType.noseBase: 1,
    FaceLandmarkType.mouthLeft: 61,
    FaceLandmarkType.mouthRight: 291,
    FaceLandmarkType.mouthBottom: 17,
  };

  @override
  Future<Result<Map<FaceLandmarkType, Confidence>, AnalyzerError>> analyze(
    FrameData frame,
  ) async {
    try {
      final raw = await _channel.detectFaceLandmarks(frame);
      final found = raw['found'] as bool? ?? false;
      if (!found) {
        return const Ok({});
      }

      final landmarksRaw = raw['landmarks'];
      if (landmarksRaw is! List || landmarksRaw.length < 478) {
        return const Ok({});
      }

      final result = <FaceLandmarkType, Confidence>{};
      for (final entry in _indexMap.entries) {
        final lm = landmarksRaw[entry.value];
        if (lm is! List || lm.length < 4) continue;
        final visibility = (lm[3] as num?)?.toDouble() ?? 0.0;
        result[entry.key] = Confidence.clamped(visibility);
      }
      return Ok(result);
    } catch (e) {
      return Err(AnalyzerError('Face landmarker failed', cause: e));
    }
  }
}

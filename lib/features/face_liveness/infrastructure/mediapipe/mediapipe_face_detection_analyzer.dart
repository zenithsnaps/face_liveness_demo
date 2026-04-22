import '../../../../core/result.dart';
import '../../domain/entities/face_detection.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/value_objects/confidence.dart';
import '../../domain/value_objects/rect2d.dart';
import '../platform_channels/mediapipe_channel.dart';

/// Runs MediaPipe Face Detector on a single frame via [MediaPipeChannel].
///
/// Native returns [{confidence, bbox: {left, top, width, height}}] per face.
/// Used only for post-capture validation, not for real-time streaming.
class MediaPipeFaceDetectionAnalyzer {
  final MediaPipeChannel _channel;
  MediaPipeFaceDetectionAnalyzer(this._channel);

  Future<Result<List<FaceDetection>, AnalyzerError>> analyze(FrameData frame) async {
    try {
      final raw = await _channel.detectFaces(frame);
      final detections = raw.map(_decode).whereType<FaceDetection>().toList();
      return Ok(detections);
    } catch (e) {
      return Err(AnalyzerError('Face detection failed', cause: e));
    }
  }

  FaceDetection? _decode(Map<String, Object?> map) {
    final bboxRaw = map['bbox'];
    if (bboxRaw is! Map) return null;
    final bbox = bboxRaw.map((k, v) => MapEntry(k.toString(), v));
    final left = (bbox['left'] as num?)?.toDouble();
    final top = (bbox['top'] as num?)?.toDouble();
    final width = (bbox['width'] as num?)?.toDouble();
    final height = (bbox['height'] as num?)?.toDouble();
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    final conf = (map['confidence'] as num?)?.toDouble() ?? 0;
    return FaceDetection(
      boundingBox: Rect2D.fromLTWH(left, top, width, height),
      score: Confidence.clamped(conf),
    );
  }
}

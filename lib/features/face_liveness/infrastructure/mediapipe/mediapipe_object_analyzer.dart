import '../../../../core/result.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/object_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/object_analyzer.dart';
import '../../domain/value_objects/confidence.dart';
import '../../domain/value_objects/rect2d.dart';
import '../platform_channels/mediapipe_channel.dart';

/// [ObjectAnalyzer] backed by MediaPipe Tasks ObjectDetector via [MediaPipeChannel].
///
/// Native side returns a list of objects in the form:
///   [
///     {
///       "label": "cell phone",
///       "confidence": 0.87,
///       "bbox": {"left": x, "top": y, "width": w, "height": h}
///     },
///     ...
///   ]
class MediaPipeObjectAnalyzer implements ObjectAnalyzer {
  final MediaPipeChannel _channel;
  MediaPipeObjectAnalyzer(this._channel);

  @override
  Future<void> initialize() => _channel.initialize();

  @override
  Future<Result<List<ObjectSnapshot>, AnalyzerError>> analyze(FrameData frame) async {
    try {
      final raw = await _channel.detectObjects(frame);
      final snapshots =
          raw.map(_decodeObject).whereType<ObjectSnapshot>().toList();
      return Ok(snapshots);
    } catch (e) {
      return Err(AnalyzerError('Object detection failed', cause: e));
    }
  }

  ObjectSnapshot? _decodeObject(Map<String, Object?> map) {
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
    final label = (map['label'] as String?) ?? 'unknown';
    final conf = (map['confidence'] as num?)?.toDouble() ?? 0;
    return ObjectSnapshot(
      boundingBox: Rect2D.fromLTWH(left, top, width, height),
      label: label,
      confidence: Confidence.clamped(conf),
    );
  }

  @override
  Future<void> dispose() => _channel.dispose();
}

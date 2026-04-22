import '../../../../core/result.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/hand_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/hand_analyzer.dart';
import '../../domain/value_objects/confidence.dart';
import '../../domain/value_objects/point2d.dart';
import '../platform_channels/mediapipe_channel.dart';

/// [HandAnalyzer] backed by MediaPipe Tasks HandLandmarker via [MediaPipeChannel].
///
/// Native side returns a list like:
///   [
///     {
///       "handedness": "Left"|"Right",
///       "confidence": double,
///       "landmarks": [[x, y], [x, y], ... 21 entries ...]
///     },
///     ...
///   ]
/// Landmark coordinates are already in frame pixel space (native does the
/// normalized-→-pixel conversion so the Flutter side stays thin).
class MediaPipeHandAnalyzer implements HandAnalyzer {
  final MediaPipeChannel _channel;
  MediaPipeHandAnalyzer(this._channel);

  @override
  Future<void> initialize() => _channel.initialize();

  @override
  Future<Result<List<HandSnapshot>, AnalyzerError>> analyze(FrameData frame) async {
    try {
      final raw = await _channel.detectHands(frame);
      final snapshots = raw.map(_decodeHand).whereType<HandSnapshot>().toList();
      return Ok(snapshots);
    } catch (e) {
      return Err(AnalyzerError('Hand detection failed', cause: e));
    }
  }

  HandSnapshot? _decodeHand(Map<String, Object?> map) {
    final lmRaw = map['landmarks'];
    if (lmRaw is! List) return null;
    if (lmRaw.length != 21) return null;
    final points = <Point2D>[];
    for (final item in lmRaw) {
      if (item is! List || item.length < 2) return null;
      final x = (item[0] as num).toDouble();
      final y = (item[1] as num).toDouble();
      points.add(Point2D(x, y));
    }
    final conf = (map['confidence'] as num?)?.toDouble() ?? 0.0;
    final hRaw = (map['handedness'] as String?)?.toLowerCase();
    final handedness = switch (hRaw) {
      'left' => Handedness.left,
      'right' => Handedness.right,
      _ => Handedness.unknown,
    };
    return HandSnapshot(
      landmarks: points,
      confidence: Confidence.clamped(conf),
      handedness: handedness,
    );
  }

  @override
  Future<void> dispose() => _channel.dispose();
}

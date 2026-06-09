import 'dart:math' as math;

import '../../../../core/app_constants.dart';
import '../../../../core/result.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/glasses_evidence.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/glasses_classifier_analyzer.dart';
import '../../domain/value_objects/rect2d.dart';
import '../platform_channels/mediapipe_channel.dart';

/// [GlassesClassifierAnalyzer] backed by MediaPipe Tasks ImageClassifier via
/// [MediaPipeChannel] — replaces the `tflite_flutter` implementation (kept as
/// `tools/glasses_export/tflite_glasses_classifier_analyzer.dart.reference`),
/// which couldn't link on iOS alongside MediaPipe (duplicate TFLite symbols).
///
/// The native side runs the MediaPipe-shaped model (NHWC + NormalizationOptions
/// metadata; see `tools/glasses_export/export_onnx_mediapipe.py`) and returns
/// `P(sunglasses)` directly. We pass the expanded, clamped face box as a
/// NORMALIZED `[0,1]` region of interest so MediaPipe does the crop + resize +
/// normalize — matching the old analyzer's `faceBox.expanded(0.6)` crop.
class MediaPipeGlassesClassifierAnalyzer implements GlassesClassifierAnalyzer {
  final MediaPipeChannel _channel;
  final double threshold;
  final double cropMargin;

  MediaPipeGlassesClassifierAnalyzer(
    this._channel, {
    this.threshold = AppConstants.glassesBlockThreshold,
    this.cropMargin = AppConstants.glassesFaceCropMargin,
  });

  Future<void> initialize() => _channel.initialize();

  @override
  Future<Result<GlassesEvidence, AnalyzerError>> analyze(
    FrameData frame, {
    Rect2D? faceBox,
  }) async {
    try {
      final imgW = frame.width;
      final imgH = frame.height;
      if (imgW <= 0 || imgH <= 0) {
        return const Err(AnalyzerError('glasses: empty frame'));
      }

      final roi = _normalizedRoi(faceBox, imgW, imgH);
      final proba = await _channel.classifyGlasses(frame, roi: roi);
      return Ok(GlassesEvidence(sunglassesProba: proba, threshold: threshold));
    } catch (e) {
      return Err(AnalyzerError('glasses classifier failed', cause: e));
    }
  }

  /// Face box expanded by [cropMargin] and clamped to the frame, expressed as a
  /// normalized `[0,1]` rect. Returns null (→ classify whole frame) when there
  /// is no box or the expanded crop collapses.
  Map<String, double>? _normalizedRoi(Rect2D? faceBox, int imgW, int imgH) {
    if (faceBox == null) return null;
    final e = faceBox.expanded(cropMargin);
    final left = math.max(0.0, e.left);
    final top = math.max(0.0, e.top);
    final right = math.min(imgW.toDouble(), e.right);
    final bottom = math.min(imgH.toDouble(), e.bottom);
    if (right - left < 8 || bottom - top < 8) return null;
    return {
      'left': left / imgW,
      'top': top / imgH,
      'width': (right - left) / imgW,
      'height': (bottom - top) / imgH,
    };
  }

  @override
  Future<void> dispose() async {
    // Native models are torn down by MediaPipeChannel.dispose(), shared with
    // the other analyzers — nothing to release per-instance here.
  }
}

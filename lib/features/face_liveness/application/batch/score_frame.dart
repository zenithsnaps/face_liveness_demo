import 'package:meta/meta.dart';

import '../../domain/entities/eye_occlusion_evidence.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/glasses_evidence.dart';

/// One frame's worth of pre-capture scores plus the upright RGBA frame to be
/// saved when this frame wins the batch.
///
/// All three scores are computed per-frame in [ScoreFrameAnalyzer.analyze]
/// from MediaPipe face detection, MediaPipe hand landmarker, and the
/// EyeOcclusionUtil pixel analysis.
@immutable
class ScoreFrame {
  /// Max MediaPipe face confidence in the frame (0.0–1.0). Higher is better.
  final double faceScore;

  /// Max hand confidence in the frame (0.0–1.0); 0 when no hand detected.
  /// Kept for diagnostics — the count below is what the result UI surfaces.
  final double handScore;

  /// Number of hands in the frame with confidence ≥
  /// [PreCaptureScoreThresholds.handBlockThreshold].
  final int handCount;

  /// Eye-occlusion combined score (0.0–1.0); 0 when the pixel analysis ran
  /// successfully and the eyes are clearly visible.
  final double sunglassesScore;

  /// Full pixel-analysis evidence — carried through to ResultScreen / Supabase
  /// so threshold tuning UIs continue to work.
  final EyeOcclusionEvidence? eyeEvidence;

  /// On-device TFLite sunglasses classifier output (null when the model errored
  /// or no face box was available). More robust than [eyeEvidence]; see
  /// docs/glasses_classifier_compare.jpg.
  final GlassesEvidence? glassesEvidence;

  /// Original sensor-orientation frame. Held only long enough to encode the
  /// JPEG and recycle.
  final FrameData frame;

  const ScoreFrame({
    required this.faceScore,
    required this.handScore,
    required this.handCount,
    required this.sunglassesScore,
    required this.eyeEvidence,
    required this.frame,
    this.glassesEvidence,
  });
}

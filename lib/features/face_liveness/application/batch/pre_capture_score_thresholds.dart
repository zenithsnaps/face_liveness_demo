import 'package:meta/meta.dart';

import '../../../../core/app_constants.dart';
import '../utils/eye_occlusion_thresholds.dart';

/// Per-frame scoring settings for the pre-capture session.
///
/// No pass/fail thresholds — these only configure how the scoring stage
/// counts hands and computes the eye-occlusion evidence shown on the result
/// screen.
@immutable
class PreCaptureScoreThresholds {
  /// Hands with confidence ≥ this value contribute to the per-frame
  /// `handCount`. Default matches the production cutoff (0.10).
  final double handBlockThreshold;

  /// Pixel-analysis thresholds for [EyeOcclusionUtil] (cheek/eye luminance,
  /// stdDev, saturation buckets, and combined-score block point). The
  /// `occluded` field on the evidence reflects this, but the result screen
  /// surfaces the raw values for review.
  final EyeOcclusionThresholds eyeThresholds;

  const PreCaptureScoreThresholds({
    this.handBlockThreshold = AppConstants.preCaptureHandBlockThreshold,
    this.eyeThresholds = EyeOcclusionThresholds.defaults,
  });

  static const defaults = PreCaptureScoreThresholds();
}

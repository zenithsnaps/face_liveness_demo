import 'package:meta/meta.dart';

/// Pixel-analysis measurements from the post-capture eye-occlusion check.
/// Carried on [CaptureValidationResult] for debugging and threshold tuning.
@immutable
class EyeOcclusionEvidence {
  /// Mean luminance of the cheek reference patch (0–255).
  final double referenceLuminance;

  /// Eye luminance / cheek luminance ratio (lower = darker relative to skin).
  final double leftLumRatio;
  final double rightLumRatio;

  /// Standard deviation of luminance inside the eye region (lower = flatter/more uniform).
  final double leftStdDev;
  final double rightStdDev;

  /// Mean absolute saturation per pixel = mean(max(R,G,B) − min(R,G,B)), 0–255.
  /// Lower = more grey/desaturated (typical of a dark lens).
  final double leftSaturation;
  final double rightSaturation;

  /// Combined score per eye (0 = clearly open, 1 = clearly occluded).
  final double leftScore;
  final double rightScore;

  /// Worst-eye combined score used for the final pass/fail decision.
  final double combinedScore;

  /// True when [combinedScore] ≥ [AppConstants.eyeOcclusionBlockScore].
  final bool occluded;

  const EyeOcclusionEvidence({
    required this.referenceLuminance,
    required this.leftLumRatio,
    required this.rightLumRatio,
    required this.leftStdDev,
    required this.rightStdDev,
    required this.leftSaturation,
    required this.rightSaturation,
    required this.leftScore,
    required this.rightScore,
    required this.combinedScore,
    required this.occluded,
  });

  @override
  String toString() =>
      'EyeOcclusionEvidence('
      'refLum=${referenceLuminance.toStringAsFixed(1)}, '
      'lumRatio=${leftLumRatio.toStringAsFixed(2)}/${rightLumRatio.toStringAsFixed(2)}, '
      'stdDev=${leftStdDev.toStringAsFixed(1)}/${rightStdDev.toStringAsFixed(1)}, '
      'sat=${leftSaturation.toStringAsFixed(1)}/${rightSaturation.toStringAsFixed(1)}, '
      'score=${leftScore.toStringAsFixed(2)}/${rightScore.toStringAsFixed(2)}, '
      'combined=${combinedScore.toStringAsFixed(2)}, '
      'occluded=$occluded)';
}

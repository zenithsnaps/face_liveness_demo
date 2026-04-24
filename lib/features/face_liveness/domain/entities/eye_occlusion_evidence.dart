import 'package:meta/meta.dart';

/// Pixel-analysis measurements from the post-capture eye-occlusion check.
/// Carried on [CaptureValidationResult] for debugging and threshold tuning.
@immutable
class EyeOcclusionEvidence {
  /// Mean luminance (0–255) inside the left/right eye contour bbox.
  final double leftEyeLuminance;
  final double rightEyeLuminance;

  /// Mean HSV saturation (0–1) inside the left/right eye contour bbox.
  final double leftEyeSaturation;
  final double rightEyeSaturation;

  /// Mean luminance/saturation of the cheek reference patch.
  final double referenceLuminance;
  final double referenceSaturation;

  /// referenceLuminance − eyeLuminance for each eye (positive = eye is darker).
  final double leftContrast;
  final double rightContrast;

  /// True when all three occlusion signals triggered for both eyes.
  final bool occluded;

  const EyeOcclusionEvidence({
    required this.leftEyeLuminance,
    required this.rightEyeLuminance,
    required this.leftEyeSaturation,
    required this.rightEyeSaturation,
    required this.referenceLuminance,
    required this.referenceSaturation,
    required this.leftContrast,
    required this.rightContrast,
    required this.occluded,
  });

  @override
  String toString() =>
      'EyeOcclusionEvidence('
      'L=$leftEyeLuminance/${leftEyeSaturation.toStringAsFixed(2)}, '
      'R=$rightEyeLuminance/${rightEyeSaturation.toStringAsFixed(2)}, '
      'ref=$referenceLuminance, '
      'contrast=${leftContrast.toStringAsFixed(1)}/${rightContrast.toStringAsFixed(1)}, '
      'occluded=$occluded)';
}

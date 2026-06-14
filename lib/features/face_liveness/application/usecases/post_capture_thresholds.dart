import '../../../../core/app_constants.dart';

/// Runtime-tunable thresholds for post-capture validation.
///
/// Defaults mirror [AppConstants] and can be overridden by the user on the
/// home screen before starting verification.
class PostCaptureThresholds {
  /// Minimum face detection score for the captured photo to pass (0.0–1.0).
  final double faceScore;

  /// Any detected hand with confidence ≥ this value blocks the capture (0.0–1.0).
  final double handConfidence;

  /// Nose/mouth landmark visibility must be ≥ this value; lower fails the
  /// occlusion check (0.0–1.0).
  final double landmarkVisibility;

  /// Sunglasses classifier probability at/above which the capture is blocked
  /// as eye-occluded (0.0–1.0). Drives both the post-capture gate and the
  /// per-frame "is wearing sunglasses" emphasis on the result screen.
  final double glassesThreshold;

  const PostCaptureThresholds({
    required this.faceScore,
    required this.handConfidence,
    required this.landmarkVisibility,
    required this.glassesThreshold,
  });

  static const defaults = PostCaptureThresholds(
    faceScore: AppConstants.faceDetectionMinScore,
    handConfidence: AppConstants.postCaptureHandMinConfidence,
    landmarkVisibility: AppConstants.landmarkVisibilityThreshold,
    glassesThreshold: AppConstants.glassesBlockThreshold,
  );

  PostCaptureThresholds copyWith({
    double? faceScore,
    double? handConfidence,
    double? landmarkVisibility,
    double? glassesThreshold,
  }) =>
      PostCaptureThresholds(
        faceScore: faceScore ?? this.faceScore,
        handConfidence: handConfidence ?? this.handConfidence,
        landmarkVisibility: landmarkVisibility ?? this.landmarkVisibility,
        glassesThreshold: glassesThreshold ?? this.glassesThreshold,
      );
}

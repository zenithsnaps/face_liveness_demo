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

  const PostCaptureThresholds({
    required this.faceScore,
    required this.handConfidence,
    required this.landmarkVisibility,
  });

  static const defaults = PostCaptureThresholds(
    faceScore: AppConstants.faceDetectionMinScore,
    handConfidence: AppConstants.postCaptureHandMinConfidence,
    landmarkVisibility: AppConstants.landmarkVisibilityThreshold,
  );

  PostCaptureThresholds copyWith({
    double? faceScore,
    double? handConfidence,
    double? landmarkVisibility,
  }) =>
      PostCaptureThresholds(
        faceScore: faceScore ?? this.faceScore,
        handConfidence: handConfidence ?? this.handConfidence,
        landmarkVisibility: landmarkVisibility ?? this.landmarkVisibility,
      );
}

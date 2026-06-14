/// Toggles for the post-capture validation checks.
///
/// All default to enabled. When a check is disabled, its analyzer is skipped
/// entirely and never produces a failure.
class PostCaptureChecks {
  /// Run MediaPipe face detection and enforce the face-score threshold.
  final bool faceEnabled;

  /// Run MediaPipe hand landmarker and fail if any confident hand is detected.
  final bool handEnabled;

  /// Run ML Kit eye-contour analysis to detect sunglasses / eye-covering objects.
  final bool eyeOcclusionEnabled;

  /// Run the on-device TFLite sunglasses classifier (more robust than the
  /// pixel-statistic [eyeOcclusionEnabled] check; see
  /// `docs/glasses_classifier_compare.jpg`).
  final bool glassesEnabled;

  const PostCaptureChecks({
    required this.faceEnabled,
    required this.handEnabled,
    required this.eyeOcclusionEnabled,
    required this.glassesEnabled,
  });

  static const defaults = PostCaptureChecks(
    faceEnabled: true,
    handEnabled: true,
    eyeOcclusionEnabled: true,
    glassesEnabled: true,
  );

  PostCaptureChecks copyWith({
    bool? faceEnabled,
    bool? handEnabled,
    bool? eyeOcclusionEnabled,
    bool? glassesEnabled,
  }) =>
      PostCaptureChecks(
        faceEnabled: faceEnabled ?? this.faceEnabled,
        handEnabled: handEnabled ?? this.handEnabled,
        eyeOcclusionEnabled: eyeOcclusionEnabled ?? this.eyeOcclusionEnabled,
        glassesEnabled: glassesEnabled ?? this.glassesEnabled,
      );
}

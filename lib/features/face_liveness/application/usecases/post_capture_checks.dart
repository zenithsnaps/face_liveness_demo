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

  const PostCaptureChecks({
    required this.faceEnabled,
    required this.handEnabled,
    required this.eyeOcclusionEnabled,
  });

  static const defaults = PostCaptureChecks(
    faceEnabled: true,
    handEnabled: true,
    eyeOcclusionEnabled: true,
  );

  PostCaptureChecks copyWith({
    bool? faceEnabled,
    bool? handEnabled,
    bool? eyeOcclusionEnabled,
  }) =>
      PostCaptureChecks(
        faceEnabled: faceEnabled ?? this.faceEnabled,
        handEnabled: handEnabled ?? this.handEnabled,
        eyeOcclusionEnabled: eyeOcclusionEnabled ?? this.eyeOcclusionEnabled,
      );
}

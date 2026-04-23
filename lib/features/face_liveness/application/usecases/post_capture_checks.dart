/// Toggles for the MediaPipe analyzers in the post-capture validation step.
///
/// Both default to enabled. When a check is disabled, its analyzer is skipped
/// entirely and never produces a failure.
class PostCaptureChecks {
  /// Run MediaPipe face detection and enforce the face-score threshold.
  final bool faceEnabled;

  /// Run MediaPipe hand landmarker and fail if any confident hand is detected.
  final bool handEnabled;

  const PostCaptureChecks({
    required this.faceEnabled,
    required this.handEnabled,
  });

  static const defaults =
      PostCaptureChecks(faceEnabled: true, handEnabled: true);

  PostCaptureChecks copyWith({bool? faceEnabled, bool? handEnabled}) =>
      PostCaptureChecks(
        faceEnabled: faceEnabled ?? this.faceEnabled,
        handEnabled: handEnabled ?? this.handEnabled,
      );
}

/// Toggles for pre-capture (live preview) checks inside the face-quality gate.
///
/// When a check is disabled, the corresponding guard in [CheckFaceQuality] is
/// skipped and never produces a failure.
class PreCaptureChecks {
  /// Enforce both eye landmarks visible AND both eyes open above threshold.
  final bool eyesEnabled;

  const PreCaptureChecks({
    required this.eyesEnabled,
  });

  static const defaults = PreCaptureChecks(eyesEnabled: true);

  PreCaptureChecks copyWith({bool? eyesEnabled}) =>
      PreCaptureChecks(eyesEnabled: eyesEnabled ?? this.eyesEnabled);
}

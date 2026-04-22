/// The 3 ordered gates a user must pass before capture.
///
/// Occlusion is validated silently post-capture via [ValidateCapture],
/// not as separate real-time gates.
enum LivenessGate {
  faceQuality,   // Gate 1 — face fills the frame, head pose, eyes open
  livenessSmile, // Gate 2 — smile challenge
  livenessBlink; // Gate 3 — blink challenge

  static const List<LivenessGate> orderedPipeline = [
    faceQuality,
    livenessSmile,
    livenessBlink,
  ];
}

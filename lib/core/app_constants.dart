class AppConstants {
  const AppConstants._();

  // Gate 1a — smile challenge
  static const double smileLowThreshold = 0.2;
  static const double smileHighThreshold = 0.7;

  // Gate 1b — blink challenge
  static const double eyeClosedThreshold = 0.3;
  static const double eyeOpenThreshold = 0.7;

  // Gate 2 — face fills frame (ratios of oval guide width)
  static const double faceBboxMinRatio = 0.80; // below → "ขยับเข้าใกล้กล้อง"
  static const double faceBboxTargetRatio = 0.90; // minimum to pass
  static const double faceBboxMaxRatio = 0.98; // above → "ขยับออกเล็กน้อย"
  static const double faceQualityEyeOpenMinThreshold = 0.7;

  // Gate 3 — object occlusion
  static const double landmarkVisibilityThreshold = 0.7;
  static const double objectBboxOverlapThreshold = 0.1;
  static const double objectDetectionMinConfidence = 0.5;
  // "person" is always the user themselves, not an occlusion source.
  static const Set<String> objectOcclusionExcludedLabels = {'person'};

  // Gate 4 — hand occlusion (real-time, kept for reference)
  static const double faceBboxExpansionForHand = 0.15; // 15% expansion
  static const List<int> fingertipLandmarkIndices = [4, 8, 12, 16, 20];
  static const double handDetectionMinConfidence = 0.5;

  // Post-capture validation thresholds
  static const double faceDetectionMinScore = 0.50;
  static const double postCaptureHandMinConfidence = 0.10;

  // Eye-occlusion detection thresholds. Ported 1:1 from production
  // (FaceDetectionUtils.isWearingSunglasses) — weighted-bucket scoring:
  //   Lum ratio  < block → +0.45,  < pass → +0.30
  //   StdDev     < block → +0.30,  < pass → +0.18
  //   Saturation < block → +0.25,  < pass → +0.15  (HSV: (max-min)/max * 255)
  // Total ≥ blockScore → fail. 0.30 = suspicious (one strong signal trips it).
  static const double eyeLumRatioPass = 0.55;
  static const double eyeLumRatioBlock = 0.35;
  static const double eyeStdDevPass = 15.0;
  static const double eyeStdDevBlock = 8.0;
  static const double eyeSaturationPass = 20.0;
  static const double eyeSaturationBlock = 12.0;
  static const double eyeOcclusionBlockScore = 0.30;

  // Flow machine
  static const int debounceFrames = 5;
  static const Duration gateTimeout = Duration(seconds: 20);

  // Pre-capture capture session: while the face is inside the oval, the
  // coordinator collects this many stream frames (configurable in the UI,
  // 1..30) and shows them on the result screen along with per-frame metrics.
  // No pass/fail decision is made — the result screen is purely informational.
  static const int captureFrameCountDefault = 10;
  static const int captureFrameCountMin = 1;
  static const int captureFrameCountMax = 30;
  // Legacy 5-frame batch constant kept for tests still referencing it.
  static const int batchFrameCount = 5;
  // Hands with confidence at/above this value count toward the per-frame
  // hand count surfaced on the result screen.
  static const double preCaptureHandBlockThreshold = 0.10;

  // Head pose (for "look straight")
  static const double headPoseMaxYawDegrees = 15.0;
  static const double headPoseMaxPitchDegrees = 15.0;
  static const double headPoseMaxRollDegrees = 15.0;

  // MediaPipe platform channel
  static const String mediaPipeChannelName = 'app.mymo/mediapipe';

  // Max simultaneously detected hands
  static const int maxHands = 2;

  // Face landmarker (post-capture occlusion check)
  static const String faceLandmarkerModelAsset = 'assets/models/face_landmarker.task';
  static const double faceLandmarkerMinDetectionConfidence = 0.5;
}

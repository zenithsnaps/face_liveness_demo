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

  // Eye-occlusion pixel-analysis thresholds (post-capture)
  static const double eyeMaxLuminanceDefault = 60.0;          // 0–255; below = dark eye region
  static const double eyeMaxSaturationDefault = 0.25;          // 0–1; below = grey/flat lens
  static const double eyeMinContrastVsReferenceDefault = 70.0; // 0–255; eye must be this much darker than cheek

  // Flow machine
  static const int debounceFrames = 5;
  static const Duration gateTimeout = Duration(seconds: 20);

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

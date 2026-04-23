import 'dart:math' as math;

import '../../domain/entities/frame_data.dart';
import '../../domain/entities/frame_metadata.dart';
import '../../domain/entities/hand_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/face_landmarker_analyzer.dart';
import '../../domain/repositories/hand_analyzer.dart';
import '../../infrastructure/mediapipe/mediapipe_face_detection_analyzer.dart';
import 'post_capture_checks.dart';
import 'post_capture_thresholds.dart';

/// Result of post-capture validation. Always populated regardless of pass/fail
/// so callers can surface partial data for threshold tuning.
class CaptureValidationResult {
  /// Best face detection score found in the frame (0.0–1.0).
  /// null only when the face analyzer itself errored out or face check is disabled.
  final double? faceScore;

  /// Non-null when validation failed.
  final LivenessFailure? failure;

  /// All detected face scores (including those below threshold).
  final List<double> faceScores;

  /// Total number of faces detected by the face detector.
  final int facesDetected;

  /// Hands that exceeded the post-capture confidence threshold.
  final List<HandSnapshot> hands;

  /// Count of hands exceeding the post-capture confidence threshold.
  final int handsDetected;

  /// Metadata of the decoded JPEG frame (dimensions, rotation).
  final FrameMetadata? frameMeta;

  const CaptureValidationResult({
    this.faceScore,
    this.failure,
    this.faceScores = const [],
    this.facesDetected = 0,
    this.hands = const [],
    this.handsDetected = 0,
    this.frameMeta,
  });

  bool get passed => failure == null;
}

/// Post-capture validation (runs after [camera.takePicture]).
///
/// Evaluation order:
///   1. Face analyzer error → [LivenessFailure.analyzerError]  (if faceEnabled)
///   2. Hand analyzer error → [LivenessFailure.analyzerError]  (if handEnabled)
///   3. Any confident hand present → [LivenessFailure.handOccluding]  (if handEnabled)
///   4. No face passes score ≥ [PostCaptureThresholds.faceScore] → [LivenessFailure.noFace]  (if faceEnabled)
///   5. All clear → passed with [faceScore]
class ValidateCapture {
  final MediaPipeFaceDetectionAnalyzer _faceAnalyzer;
  final HandAnalyzer _handAnalyzer;
  // ignore: unused_field
  final FaceLandmarkerAnalyzer _faceLandmarkerAnalyzer;

  const ValidateCapture({
    required MediaPipeFaceDetectionAnalyzer faceAnalyzer,
    required HandAnalyzer handAnalyzer,
    required FaceLandmarkerAnalyzer faceLandmarkerAnalyzer,
  })  : _faceAnalyzer = faceAnalyzer,
        _handAnalyzer = handAnalyzer,
        _faceLandmarkerAnalyzer = faceLandmarkerAnalyzer;

  Future<CaptureValidationResult> call(
    FrameData frame, {
    PostCaptureThresholds thresholds = PostCaptureThresholds.defaults,
    PostCaptureChecks checks = PostCaptureChecks.defaults,
  }) async {
    final meta = frame.metadata;

    // Kick off only the enabled detections, concurrently where both are on.
    final faceFuture = checks.faceEnabled ? _faceAnalyzer.analyze(frame) : null;
    final handFuture = checks.handEnabled ? _handAnalyzer.analyze(frame) : null;
    final faceResult = await faceFuture;
    final handResult = await handFuture;

    // --- Face ---
    var allScores = <double>[];
    var facesDetected = 0;
    double? bestPassing;
    double? bestAny;

    if (faceResult != null) {
      if (faceResult.isErr) {
        return CaptureValidationResult(
          failure: LivenessFailure.analyzerError,
          frameMeta: meta,
        );
      }
      final faces = faceResult.okOrNull!;
      allScores = faces.map((f) => f.score.value).toList();
      facesDetected = faces.length;
      bestAny = faces.isEmpty ? null : allScores.reduce(math.max);
      final passing =
          faces.where((f) => f.score.value >= thresholds.faceScore).toList();
      bestPassing = passing.isEmpty
          ? null
          : passing.map((f) => f.score.value).reduce(math.max);
    }

    // --- Hand (fail-safe: error = treat as blocked, never silently whitelist) ---
    if (handResult != null) {
      if (handResult.isErr) {
        return CaptureValidationResult(
          faceScore: bestPassing ?? bestAny,
          failure: LivenessFailure.analyzerError,
          faceScores: allScores,
          facesDetected: facesDetected,
          frameMeta: meta,
        );
      }
      final allHands = handResult.okOrNull!;
      final confidentHands = allHands
          .where((h) => h.confidence.value >= thresholds.handConfidence)
          .toList();
      if (confidentHands.isNotEmpty) {
        return CaptureValidationResult(
          faceScore: bestPassing ?? bestAny,
          failure: LivenessFailure.handOccluding,
          faceScores: allScores,
          facesDetected: facesDetected,
          hands: confidentHands,
          handsDetected: confidentHands.length,
          frameMeta: meta,
        );
      }
    }

    // --- Face threshold check (only when face check is enabled) ---
    if (faceResult != null && bestPassing == null) {
      return CaptureValidationResult(
        faceScore: bestAny,
        failure: LivenessFailure.noFace,
        faceScores: allScores,
        facesDetected: facesDetected,
        frameMeta: meta,
      );
    }

    // TODO: FaceLandmarker occlusion check temporarily disabled.

    return CaptureValidationResult(
      faceScore: bestPassing,
      faceScores: allScores,
      facesDetected: facesDetected,
      frameMeta: meta,
    );
  }
}

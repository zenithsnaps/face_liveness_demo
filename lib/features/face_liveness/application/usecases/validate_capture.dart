import 'dart:math' as math;

import '../../../../core/app_constants.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/frame_metadata.dart';
import '../../domain/entities/hand_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/hand_analyzer.dart';
import '../../infrastructure/mediapipe/mediapipe_face_detection_analyzer.dart';

/// Result of post-capture validation. Always populated regardless of pass/fail
/// so callers can surface partial data for threshold tuning.
class CaptureValidationResult {
  /// Best face detection score found in the frame (0.0–1.0).
  /// null only when the face analyzer itself errored out.
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
/// Face and hand detection run **concurrently** so that a low face score caused
/// by hand occlusion does not hide the hand failure reason.
///
/// Evaluation order (after both complete):
///   1. Face analyzer error → [LivenessFailure.analyzerError]
///   2. Hand analyzer error → [LivenessFailure.analyzerError] (fail-safe)
///   3. Any confident hand present → [LivenessFailure.handOccluding]
///   4. No face passes score ≥ [AppConstants.faceDetectionMinScore] → [LivenessFailure.noFace]
///   5. All clear → passed with [faceScore]
class ValidateCapture {
  final MediaPipeFaceDetectionAnalyzer _faceAnalyzer;
  final HandAnalyzer _handAnalyzer;

  const ValidateCapture({
    required MediaPipeFaceDetectionAnalyzer faceAnalyzer,
    required HandAnalyzer handAnalyzer,
  })  : _faceAnalyzer = faceAnalyzer,
        _handAnalyzer = handAnalyzer;

  Future<CaptureValidationResult> call(FrameData frame) async {
    final meta = frame.metadata;

    // Kick off both detections before awaiting either.
    final faceFuture = _faceAnalyzer.analyze(frame);
    final handFuture = _handAnalyzer.analyze(frame);
    final faceResult = await faceFuture;
    final handResult = await handFuture;

    // --- Face ---
    if (faceResult.isErr) {
      return CaptureValidationResult(
        failure: LivenessFailure.analyzerError,
        frameMeta: meta,
      );
    }
    final faces = faceResult.okOrNull!;
    final allScores = faces.map((f) => f.score.value).toList();
    final bestAny = faces.isEmpty ? null : allScores.reduce(math.max);
    final passing = faces
        .where((f) => f.score.value >= AppConstants.faceDetectionMinScore)
        .toList();
    final bestPassing = passing.isEmpty
        ? null
        : passing.map((f) => f.score.value).reduce(math.max);

    // --- Hand (fail-safe: error = treat as blocked, never silently whitelist) ---
    if (handResult.isErr) {
      return CaptureValidationResult(
        faceScore: bestPassing ?? bestAny,
        failure: LivenessFailure.analyzerError,
        faceScores: allScores,
        facesDetected: faces.length,
        frameMeta: meta,
      );
    }
    final allHands = handResult.okOrNull!;
    final confidentHands = allHands
        .where((h) => h.confidence.value >= AppConstants.postCaptureHandMinConfidence)
        .toList();
    if (confidentHands.isNotEmpty) {
      return CaptureValidationResult(
        faceScore: bestPassing ?? bestAny,
        failure: LivenessFailure.handOccluding,
        faceScores: allScores,
        facesDetected: faces.length,
        hands: confidentHands,
        handsDetected: confidentHands.length,
        frameMeta: meta,
      );
    }

    // --- No hand: check face threshold ---
    if (passing.isEmpty) {
      return CaptureValidationResult(
        faceScore: bestAny,
        failure: LivenessFailure.noFace,
        faceScores: allScores,
        facesDetected: faces.length,
        frameMeta: meta,
      );
    }

    return CaptureValidationResult(
      faceScore: bestPassing,
      faceScores: allScores,
      facesDetected: faces.length,
      frameMeta: meta,
    );
  }
}

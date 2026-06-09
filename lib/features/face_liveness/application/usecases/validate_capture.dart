import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../domain/entities/eye_occlusion_evidence.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/frame_metadata.dart';
import '../../domain/entities/glasses_evidence.dart';
import '../../domain/entities/hand_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/eye_contour_analyzer.dart';
import '../../domain/repositories/face_landmarker_analyzer.dart';
import '../../domain/repositories/glasses_classifier_analyzer.dart';
import '../../domain/repositories/hand_analyzer.dart';
import '../../domain/value_objects/rect2d.dart';
import '../../infrastructure/mediapipe/mediapipe_face_detection_analyzer.dart';
import 'check_no_eye_occlusion.dart';
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

  /// Pixel-analysis measurements from the eye-occlusion check (null when
  /// the check was skipped or no face was found by the contour detector).
  final EyeOcclusionEvidence? eyeEvidence;

  /// Output of the TFLite sunglasses classifier (null when the check was
  /// skipped or the model errored).
  final GlassesEvidence? glassesEvidence;

  const CaptureValidationResult({
    this.faceScore,
    this.failure,
    this.faceScores = const [],
    this.facesDetected = 0,
    this.hands = const [],
    this.handsDetected = 0,
    this.frameMeta,
    this.eyeEvidence,
    this.glassesEvidence,
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
///   5. Eye occlusion detected → [LivenessFailure.eyeOccluded]  (if eyeOcclusionEnabled)
///   6. All clear → passed with [faceScore]
class ValidateCapture {
  final MediaPipeFaceDetectionAnalyzer _faceAnalyzer;
  final HandAnalyzer _handAnalyzer;
  // ignore: unused_field
  final FaceLandmarkerAnalyzer _faceLandmarkerAnalyzer;
  final EyeContourAnalyzer _eyeContourAnalyzer;
  final CheckNoEyeOcclusion _eyeOcclusionCheck;
  final GlassesClassifierAnalyzer _glassesAnalyzer;

  const ValidateCapture({
    required MediaPipeFaceDetectionAnalyzer faceAnalyzer,
    required HandAnalyzer handAnalyzer,
    required FaceLandmarkerAnalyzer faceLandmarkerAnalyzer,
    required EyeContourAnalyzer eyeContourAnalyzer,
    required CheckNoEyeOcclusion eyeOcclusionCheck,
    required GlassesClassifierAnalyzer glassesAnalyzer,
  })  : _faceAnalyzer = faceAnalyzer,
        _handAnalyzer = handAnalyzer,
        _faceLandmarkerAnalyzer = faceLandmarkerAnalyzer,
        _eyeContourAnalyzer = eyeContourAnalyzer,
        _eyeOcclusionCheck = eyeOcclusionCheck,
        _glassesAnalyzer = glassesAnalyzer;

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
    // Bounding box of the highest-scoring face — used to crop the glasses
    // classifier's input. null when no face was detected.
    Rect2D? bestFaceBox;

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
      if (faces.isNotEmpty) {
        final top = faces.reduce(
            (a, b) => a.score.value >= b.score.value ? a : b);
        bestFaceBox = top.boundingBox;
      }
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

    // --- Sunglasses classifier (TFLite) ---
    // Best-effort like the eye-occlusion check: a model error skips the check
    // rather than blocking a clean capture. More robust than the pixel-stat
    // path below (see docs/glasses_classifier_compare.jpg).
    GlassesEvidence? glassesEvidence;
    if (checks.glassesEnabled) {
      final glassesResult =
          await _glassesAnalyzer.analyze(frame, faceBox: bestFaceBox);
      if (glassesResult.isOk) {
        glassesEvidence = glassesResult.okOrNull;
        if (glassesEvidence != null && glassesEvidence.isWearingSunglasses) {
          return CaptureValidationResult(
            faceScore: bestPassing,
            failure: LivenessFailure.eyeOccluded,
            faceScores: allScores,
            facesDetected: facesDetected,
            frameMeta: meta,
            glassesEvidence: glassesEvidence,
          );
        }
      } else {
        debugPrint('[Glasses] skipped: ${glassesResult.errOrNull}');
      }
    }

    // --- Eye-occlusion pixel analysis ---
    // Failures here are best-effort: if ML Kit can't find the face or errors out,
    // we skip rather than blocking a clean capture on an analyzer hiccup.
    debugPrint('[EyeOcclusion] reached check block — '
        'eyeOcclusionEnabled=${checks.eyeOcclusionEnabled} '
        'frame=${frame.width}x${frame.height}');
    EyeOcclusionEvidence? eyeEvidence;
    if (checks.eyeOcclusionEnabled) {
      final regionsResult = await _eyeContourAnalyzer.analyze(frame);
      debugPrint('[EyeOcclusion] contour result: '
          'isOk=${regionsResult.isOk} '
          'hasRegions=${regionsResult.okOrNull != null} '
          'err=${regionsResult.errOrNull}');
      if (regionsResult.isOk && regionsResult.okOrNull != null) {
        final regions = regionsResult.okOrNull!;
        debugPrint('[EyeOcclusion] leftEye pts=${regions.leftEye.length} '
            'rightEye pts=${regions.rightEye.length} '
            'leftCheek=${regions.leftCheek} '
            'rightCheek=${regions.rightCheek}');
        final evidence = _eyeOcclusionCheck(frame: frame, regions: regions);
        debugPrint('[EyeOcclusion] evidence: $evidence');
        eyeEvidence = evidence;
        if (evidence.occluded) {
          return CaptureValidationResult(
            faceScore: bestPassing,
            failure: LivenessFailure.eyeOccluded,
            faceScores: allScores,
            facesDetected: facesDetected,
            frameMeta: meta,
            eyeEvidence: eyeEvidence,
            glassesEvidence: glassesEvidence,
          );
        }
      }
    }

    return CaptureValidationResult(
      faceScore: bestPassing,
      faceScores: allScores,
      facesDetected: facesDetected,
      frameMeta: meta,
      eyeEvidence: eyeEvidence,
      glassesEvidence: glassesEvidence,
    );
  }
}

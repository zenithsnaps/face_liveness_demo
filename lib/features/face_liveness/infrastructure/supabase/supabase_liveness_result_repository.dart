import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/app_constants.dart';
import '../../application/usecases/validate_capture.dart';
import '../../domain/entities/attempt_draft.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/liveness_result_repository.dart';

class SupabaseLivenessResultRepository implements LivenessResultRepository {
  final SupabaseClient _client;

  const SupabaseLivenessResultRepository(this._client);

  @override
  Future<String?> persistAttempt({
    required AttemptDraft draft,
    required DateTime completedAt,
    required bool passed,
    required LivenessFailure? failure,
    required String? failureMessage,
    required double? faceScore,
    required double faceScoreThreshold,
    required CaptureValidationResult? captureValidation,
    required Uint8List? summaryPng,
    required DeviceContext device,
  }) async {
    final attemptId = draft.id;
    String? summaryPath;

    // 1. Upload summary snapshot (best-effort — failure doesn't abort the row)
    if (summaryPng != null) {
      final objectPath = 'summaries/$attemptId.png';
      try {
        await _client.storage.from('liveness-summaries').uploadBinary(
              objectPath,
              summaryPng,
              fileOptions: const FileOptions(
                contentType: 'image/png',
                upsert: false,
                cacheControl: '3600',
              ),
            );
        summaryPath = objectPath;
      } on StorageException {
        // Upload failed — row will be inserted with summary_path = null
      }
    }

    // 2. Insert row
    final meta = captureValidation?.frameMeta;
    try {
      final row = <String, dynamic>{
        'id': attemptId,
        'passed': passed,
        if (failure != null) 'failure_reason': failure.name,
        'failure_message': ?failureMessage,
        'face_score': ?faceScore,
        'face_score_threshold': faceScoreThreshold,
        'started_at': draft.startedAt.toIso8601String(),
        'completed_at': completedAt.toIso8601String(),
        'summary_bucket': summaryPath != null ? 'liveness-summaries' : null,
        'summary_path': summaryPath,
        'summary_bytes': summaryPng?.length,
        'summary_width': meta?.width,
        'summary_height': meta?.height,
        'occlusion_check': captureValidation != null
            ? _buildOcclusionCheck(captureValidation)
            : null,
        if (device.platform.isNotEmpty) 'platform': device.platform,
        if (device.appVersion.isNotEmpty) 'app_version': device.appVersion,
        if (device.deviceModel != null) 'device_model': device.deviceModel,
        if (device.cameraResolution != null)
          'camera_resolution': device.cameraResolution,
      };

      await _client.from('liveness_attempts').insert(row);
      return attemptId;
    } on PostgrestException {
      // Clean up orphan blob best-effort
      if (summaryPath != null) {
        await _client.storage
            .from('liveness-summaries')
            .remove([summaryPath]).catchError((_) => <FileObject>[]);
      }
      return null;
    }
  }

  Map<String, dynamic> _buildOcclusionCheck(CaptureValidationResult v) {
    final resultLabel = v.failure == null ? 'passed' : v.failure!.name;
    final meta = v.frameMeta;
    return {
      'ran': true,
      'result': resultLabel,
      'face_detector': {
        'faces_detected': v.facesDetected,
        'best_score': v.faceScore,
        'best_score_percent': v.faceScore != null
            ? double.parse((v.faceScore! * 100).toStringAsFixed(1))
            : null,
        'threshold': AppConstants.faceDetectionMinScore,
        'all_scores': v.faceScores,
      },
      'hand_landmarker': {
        'hands_detected': v.handsDetected,
        'threshold': AppConstants.postCaptureHandMinConfidence,
        'hands': v.hands
            .map((h) => {
                  'handedness': h.handedness.name,
                  'confidence': h.confidence.value,
                })
            .toList(),
      },
      if (meta != null)
        'frame': {
          'width': meta.width,
          'height': meta.height,
          'rotation_degrees': meta.rotationDegrees,
        },
    };
  }
}

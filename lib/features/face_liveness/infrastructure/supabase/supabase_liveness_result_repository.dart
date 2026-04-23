import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/usecases/post_capture_checks.dart';
import '../../application/usecases/post_capture_thresholds.dart';
import '../../application/usecases/validate_capture.dart';
import '../../domain/entities/attempt_draft.dart';
import '../../domain/entities/attempt_record.dart';
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
    required PostCaptureThresholds thresholds,
    required PostCaptureChecks checks,
    required CaptureValidationResult? captureValidation,
    required Uint8List? summaryPng,
    required DeviceContext device,
    required String? testCase,
  }) async {
    final attemptId = draft.id;
    String? summaryObjectPath;
    String? summaryUrl;

    // 1. Upload summary snapshot (best-effort — failure doesn't abort the row)
    if (summaryPng != null) {
      summaryObjectPath = 'summaries/$attemptId.png';
      try {
        await _client.storage.from('liveness-summaries').uploadBinary(
              summaryObjectPath,
              summaryPng,
              fileOptions: const FileOptions(
                contentType: 'image/png',
                upsert: false,
                cacheControl: '3600',
              ),
            );
        summaryUrl = _client.storage
            .from('liveness-summaries')
            .getPublicUrl(summaryObjectPath);
      } on StorageException {
        // Upload failed — row will be inserted with summary_path = null
        summaryObjectPath = null;
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
        'face_score_threshold': thresholds.faceScore,
        'face_check_enabled': checks.faceEnabled,
        'hand_check_enabled': checks.handEnabled,
        'test_case': ?testCase,
        'started_at': draft.startedAt.toIso8601String(),
        'completed_at': completedAt.toIso8601String(),
        'summary_bucket': summaryUrl != null ? 'liveness-summaries' : null,
        'summary_path': summaryUrl,
        'summary_bytes': summaryPng?.length,
        'summary_width': meta?.width,
        'summary_height': meta?.height,
        'occlusion_check': captureValidation != null
            ? _buildOcclusionCheck(captureValidation, thresholds, checks)
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
      if (summaryObjectPath != null) {
        await _client.storage
            .from('liveness-summaries')
            .remove([summaryObjectPath]).catchError((_) => <FileObject>[]);
      }
      return null;
    }
  }

  @override
  Future<List<AttemptRecord>> fetchAttempts({
    DateTime? since,
    int limit = 1000,
  }) async {
    var query = _client.from('liveness_attempts').select(
          'id, completed_at, passed, failure_reason, face_score, '
          'face_score_threshold, test_case, face_check_enabled, hand_check_enabled',
        );
    if (since != null) {
      query = query.gte('completed_at', since.toIso8601String());
    }
    final rows = await query
        .order('completed_at', ascending: false)
        .limit(limit) as List<dynamic>;
    return rows.map((r) => _toAttemptRecord(r as Map<String, dynamic>)).toList();
  }

  AttemptRecord _toAttemptRecord(Map<String, dynamic> r) {
    return AttemptRecord(
      id: r['id'] as String,
      completedAt: DateTime.parse(r['completed_at'] as String),
      passed: r['passed'] as bool,
      failureReason: r['failure_reason'] as String?,
      faceScore: (r['face_score'] as num?)?.toDouble(),
      faceScoreThreshold: (r['face_score_threshold'] as num?)?.toDouble(),
      testCase: r['test_case'] as String?,
      faceCheckEnabled: r['face_check_enabled'] as bool?,
      handCheckEnabled: r['hand_check_enabled'] as bool?,
    );
  }

  Map<String, dynamic> _buildOcclusionCheck(
      CaptureValidationResult v, PostCaptureThresholds t, PostCaptureChecks c) {
    final resultLabel = v.failure == null ? 'passed' : v.failure!.name;
    final meta = v.frameMeta;
    return {
      'ran': true,
      'result': resultLabel,
      'face_detector': {
        'enabled': c.faceEnabled,
        'faces_detected': v.facesDetected,
        'best_score': v.faceScore,
        'best_score_percent': v.faceScore != null
            ? double.parse((v.faceScore! * 100).toStringAsFixed(1))
            : null,
        'threshold': t.faceScore,
        'all_scores': v.faceScores,
      },
      'hand_landmarker': {
        'enabled': c.handEnabled,
        'hands_detected': v.handsDetected,
        'threshold': t.handConfidence,
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

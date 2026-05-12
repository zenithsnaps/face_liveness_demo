import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/app_constants.dart';
import '../../application/usecases/post_capture_checks.dart';
import '../../domain/entities/attempt_record.dart';
import '../../domain/entities/eye_occlusion_evidence.dart';
import '../../domain/repositories/liveness_result_repository.dart';
import '../../presentation/coordinators/batch_capture_coordinator.dart';

class SupabaseLivenessResultRepository implements LivenessResultRepository {
  final SupabaseClient _client;

  const SupabaseLivenessResultRepository(this._client);

  static const _bucket = 'liveness-summaries';

  @override
  Future<String?> persistSession({
    required CaptureSession session,
    required DateTime draftStartedAt,
    required DateTime completedAt,
    required DeviceContext device,
    required PostCaptureChecks checks,
    required String? testCase,
    required String? testerName,
  }) async {
    final groupId = session.groupId;
    final rows = <Map<String, dynamic>>[];
    final uploadedPaths = <String>[];

    for (final frame in session.frames) {
      final score = frame.score;
      final objectPath = 'frames/$groupId/${frame.sequence}.jpg';
      Uint8List bytes;
      try {
        bytes = await File(frame.jpegPath).readAsBytes();
      } catch (e, st) {
        debugPrint('[Persist] read JPEG failed seq=${frame.sequence}: $e\n$st');
        continue;
      }

      String? publicUrl;
      try {
        await _client.storage.from(_bucket).uploadBinary(
              objectPath,
              bytes,
              fileOptions: const FileOptions(
                contentType: 'image/jpeg',
                upsert: false,
                cacheControl: '3600',
              ),
            );
        publicUrl = _client.storage.from(_bucket).getPublicUrl(objectPath);
        uploadedPaths.add(objectPath);
      } catch (e, st) {
        debugPrint('[Persist] storage upload FAILED seq=${frame.sequence}: $e\n$st');
        publicUrl = null;
      }

      final meta = score.frame.metadata;
      // Toggles from the home screen control which per-frame metrics make
      // it into the row. The analyzers themselves still run (they share the
      // same stream pipeline that drives the face-max thumbnail selection),
      // but a disabled toggle is honoured by skipping that column so
      // downstream filters see a null instead of a value.
      rows.add({
        'group_id': groupId,
        'sequence': frame.sequence,
        'passed': true,
        'face_score': checks.faceEnabled ? score.faceScore : null,
        'face_score_threshold':
            checks.faceEnabled ? AppConstants.faceDetectionMinScore : null,
        'face_check_enabled': checks.faceEnabled,
        'hand_check_enabled': checks.handEnabled,
        'hand_count': checks.handEnabled ? score.handCount : null,
        'eye_combined': checks.eyeOcclusionEnabled
            ? score.eyeEvidence?.combinedScore
            : null,
        'started_at': draftStartedAt.toIso8601String(),
        'completed_at': completedAt.toIso8601String(),
        'summary_bucket': publicUrl != null ? _bucket : null,
        'summary_path': publicUrl,
        'summary_bytes': bytes.length,
        'summary_width': meta.width,
        'summary_height': meta.height,
        'occlusion_check': checks.eyeOcclusionEnabled
            ? _buildOcclusionCheck(score.eyeEvidence)
            : null,
        'test_case': ?testCase,
        'tester_name': ?testerName,
        if (device.platform.isNotEmpty) 'platform': device.platform,
        if (device.appVersion.isNotEmpty) 'app_version': device.appVersion,
        if (device.deviceModel != null) 'device_model': device.deviceModel,
        if (device.cameraResolution != null)
          'camera_resolution': device.cameraResolution,
      });
    }

    if (rows.isEmpty) {
      debugPrint('[Persist] nothing to insert — all frames failed to read');
      return null;
    }

    try {
      await _client.from('liveness_attempts').insert(rows);
      debugPrint('[Persist] inserted ${rows.length} rows for group=$groupId');
      return groupId;
    } catch (e, st) {
      debugPrint('[Persist] DB insert FAILED (${e.runtimeType}): $e\n$st');
      // Best-effort cleanup of orphan storage objects on insert failure.
      for (final p in uploadedPaths) {
        await _client.storage
            .from(_bucket)
            .remove([p]).catchError((_) => <FileObject>[]);
      }
      return null;
    }
  }

  @override
  Future<List<AttemptRecord>> fetchAttempts({
    DateTime? since,
    DateTime? until,
    int limit = 1000,
  }) async {
    debugPrint('[Analytics] fetchAttempts since=$since until=$until limit=$limit');
    var query = _client.from('liveness_attempts').select(
          'id, completed_at, passed, failure_reason, face_score, '
          'face_score_threshold, test_case, face_check_enabled, hand_check_enabled, '
          'device_model, summary_path, tester_name',
        );
    if (since != null) {
      query = query.gte('completed_at', since.toIso8601String());
    }
    if (until != null) {
      query = query.lte('completed_at', until.toIso8601String());
    }
    try {
      final rows = await query
          .order('completed_at', ascending: false)
          .limit(limit)
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw TimeoutException(
                'Supabase fetchAttempts ใช้เวลานานเกิน 20 วินาที'),
          ) as List<dynamic>;
      debugPrint('[Analytics] fetchAttempts ok — ${rows.length} rows');
      return rows
          .map((r) => _toAttemptRecord(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Analytics] fetchAttempts FAILED (${e.runtimeType}): $e\n$st');
      rethrow;
    }
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
      deviceModel: r['device_model'] as String?,
      summaryUrl: r['summary_path'] as String?,
      testerName: r['tester_name'] as String?,
    );
  }

  Map<String, dynamic>? _buildOcclusionCheck(EyeOcclusionEvidence? eye) {
    if (eye == null) return null;
    return {
      'evaluated': true,
      'occluded': eye.occluded,
      'combined_score': eye.combinedScore,
      'reference_luminance': eye.referenceLuminance,
      'left': {
        'lum_ratio': eye.leftLumRatio,
        'std_dev': eye.leftStdDev,
        'saturation': eye.leftSaturation,
        'score': eye.leftScore,
      },
      'right': {
        'lum_ratio': eye.rightLumRatio,
        'std_dev': eye.rightStdDev,
        'saturation': eye.rightSaturation,
        'score': eye.rightScore,
      },
    };
  }
}

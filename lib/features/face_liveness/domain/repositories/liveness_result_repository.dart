import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../application/usecases/post_capture_checks.dart';
import '../../application/usecases/post_capture_thresholds.dart';
import '../../application/usecases/validate_capture.dart';
import '../../domain/entities/attempt_draft.dart';
import '../../domain/entities/attempt_record.dart';
import '../../domain/failures/liveness_failure.dart';

@immutable
class DeviceContext {
  final String platform;
  final String appVersion;
  final String? deviceModel;
  final String? cameraResolution;

  const DeviceContext({
    required this.platform,
    required this.appVersion,
    this.deviceModel,
    this.cameraResolution,
  });

  DeviceContext copyWith({String? cameraResolution}) => DeviceContext(
        platform: platform,
        appVersion: appVersion,
        deviceModel: deviceModel,
        cameraResolution: cameraResolution ?? this.cameraResolution,
      );
}

abstract class LivenessResultRepository {
  /// Upload summary PNG (if provided) then insert a row in liveness_attempts.
  /// Returns the attempt id on success, null if persistence failed.
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
  });

  /// Fetch the most recent [limit] attempts, optionally filtered to rows
  /// completed on or after [since]. Rows are returned newest-first.
  Future<List<AttemptRecord>> fetchAttempts({
    DateTime? since,
    int limit = 1000,
  });
}

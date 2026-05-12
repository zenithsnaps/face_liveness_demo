import 'package:meta/meta.dart';

import '../../application/usecases/post_capture_checks.dart';
import '../../domain/entities/attempt_record.dart';
import '../../presentation/coordinators/batch_capture_coordinator.dart';

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
  /// Upload every captured frame in [session] as a separate row in
  /// `liveness_attempts`, sharing the same `group_id` and ordered by
  /// `sequence`. Each row carries its own JPEG (uploaded to storage) plus the
  /// per-frame face/hand/eye metrics for downstream review.
  ///
  /// Returns the group id on success, null if persistence failed.
  Future<String?> persistSession({
    required CaptureSession session,
    required DateTime draftStartedAt,
    required DateTime completedAt,
    required DeviceContext device,
    required PostCaptureChecks checks,
    required String? testCase,
    required String? testerName,
  });

  /// Fetch the most recent [limit] attempts, optionally filtered to rows
  /// completed on or after [since] and/or before [until].
  /// Rows are returned newest-first.
  Future<List<AttemptRecord>> fetchAttempts({
    DateTime? since,
    DateTime? until,
    int limit = 1000,
  });
}

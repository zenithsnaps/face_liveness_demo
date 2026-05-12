import 'package:meta/meta.dart';

@immutable
class AttemptRecord {
  final String id;
  final DateTime completedAt;
  final bool passed;
  final String? failureReason;
  final double? faceScore;
  final double? faceScoreThreshold;
  final String? testCase;
  final bool? faceCheckEnabled;
  final bool? handCheckEnabled;
  final String? deviceModel;
  final String? summaryUrl;
  final String? testerName;

  const AttemptRecord({
    required this.id,
    required this.completedAt,
    required this.passed,
    this.failureReason,
    this.faceScore,
    this.faceScoreThreshold,
    this.testCase,
    this.faceCheckEnabled,
    this.handCheckEnabled,
    this.deviceModel,
    this.summaryUrl,
    this.testerName,
  });

  /// Coarse platform inferred from [deviceModel].
  /// Anything containing "iphone" (case-insensitive) is iOS;
  /// everything else (including null) is treated as Android.
  bool get isIos =>
      (deviceModel ?? '').toLowerCase().contains('iphone');
}

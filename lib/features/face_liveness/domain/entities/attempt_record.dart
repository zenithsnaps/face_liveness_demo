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
  });
}

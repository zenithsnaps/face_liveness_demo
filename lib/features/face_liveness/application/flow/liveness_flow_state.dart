import 'package:meta/meta.dart';

import '../../domain/entities/liveness_gate.dart';
import '../../domain/failures/liveness_failure.dart';

/// Immutable state of the liveness flow state machine.
///
/// The state machine is a pure function of (State, Event) → State. All state
/// the machine needs lives here; nothing is read from clocks, streams, or I/O.
sealed class LivenessFlowState {
  const LivenessFlowState();
}

final class FlowIdle extends LivenessFlowState {
  const FlowIdle();

  @override
  bool operator ==(Object other) => other is FlowIdle;

  @override
  int get hashCode => (FlowIdle).hashCode;
}

final class FlowInitializing extends LivenessFlowState {
  const FlowInitializing();

  @override
  bool operator ==(Object other) => other is FlowInitializing;

  @override
  int get hashCode => (FlowInitializing).hashCode;
}

/// Actively evaluating a gate. [consecutivePasses] counts how many frames in a
/// row have passed the current gate — it must reach `AppConstants.debounceFrames`
/// before we advance to the next gate.
@immutable
final class FlowEvaluating extends LivenessFlowState {
  final LivenessGate gate;
  final int consecutivePasses;
  final LivenessFailure? lastFailure; // nullable transient hint for UI

  const FlowEvaluating({
    required this.gate,
    required this.consecutivePasses,
    this.lastFailure,
  });

  FlowEvaluating copyWith({
    LivenessGate? gate,
    int? consecutivePasses,
    LivenessFailure? lastFailure,
    bool clearLastFailure = false,
  }) {
    return FlowEvaluating(
      gate: gate ?? this.gate,
      consecutivePasses: consecutivePasses ?? this.consecutivePasses,
      lastFailure: clearLastFailure ? null : (lastFailure ?? this.lastFailure),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FlowEvaluating &&
          other.gate == gate &&
          other.consecutivePasses == consecutivePasses &&
          other.lastFailure == lastFailure);

  @override
  int get hashCode => Object.hash(gate, consecutivePasses, lastFailure);

  @override
  String toString() =>
      'FlowEvaluating(gate=$gate, passes=$consecutivePasses, lastFailure=$lastFailure)';
}

/// All gates passed — capture is in flight.
final class FlowCapturing extends LivenessFlowState {
  const FlowCapturing();

  @override
  bool operator ==(Object other) => other is FlowCapturing;

  @override
  int get hashCode => (FlowCapturing).hashCode;
}

@immutable
final class FlowDone extends LivenessFlowState {
  final String photoPath;
  final double? faceScore;
  const FlowDone(this.photoPath, {required this.faceScore});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FlowDone && other.photoPath == photoPath && other.faceScore == faceScore);

  @override
  int get hashCode => Object.hash(photoPath, faceScore);

  @override
  String toString() => 'FlowDone($photoPath, score=$faceScore)';
}

@immutable
final class FlowFailed extends LivenessFlowState {
  final LivenessFailure reason;
  final bool retryable;
  const FlowFailed({required this.reason, required this.retryable});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FlowFailed && other.reason == reason && other.retryable == retryable);

  @override
  int get hashCode => Object.hash(reason, retryable);

  @override
  String toString() => 'FlowFailed(reason=$reason, retryable=$retryable)';
}

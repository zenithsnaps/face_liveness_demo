import 'package:meta/meta.dart';

import '../../domain/failures/liveness_failure.dart';
import '../usecases/run_pipeline.dart';

sealed class LivenessFlowEvent {
  const LivenessFlowEvent();
}

/// User tapped the "start" button — transitions FlowIdle → FlowInitializing.
final class StartRequested extends LivenessFlowEvent {
  const StartRequested();
}

/// Camera + analyzers are ready — transitions FlowInitializing → FlowEvaluating(gate 0).
final class InitializationCompleted extends LivenessFlowEvent {
  const InitializationCompleted();
}

/// Initialization failed (permission denied, camera error, ...).
@immutable
final class InitializationFailed extends LivenessFlowEvent {
  final LivenessFailure reason;
  const InitializationFailed(this.reason);
}

/// A frame has been analyzed end-to-end and the pipeline evaluated.
@immutable
final class FrameAnalyzed extends LivenessFlowEvent {
  final PipelineFrameOutcome outcome;
  const FrameAnalyzed(this.outcome);
}

/// The current gate has been idle too long without passing.
final class TimeoutElapsed extends LivenessFlowEvent {
  const TimeoutElapsed();
}

/// User tapped retry from a FlowFailed screen.
final class UserRetry extends LivenessFlowEvent {
  const UserRetry();
}

/// Capture finished — photo is at [photoPath] with [faceScore] from post-capture validation.
@immutable
final class CaptureComplete extends LivenessFlowEvent {
  final String photoPath;
  final double? faceScore;
  const CaptureComplete(this.photoPath, {required this.faceScore});
}

/// Capture failed.
@immutable
final class CaptureFailed extends LivenessFlowEvent {
  final LivenessFailure reason;
  const CaptureFailed(this.reason);
}

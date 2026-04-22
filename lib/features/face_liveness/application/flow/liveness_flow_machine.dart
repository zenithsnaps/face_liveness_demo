import '../../../../core/app_constants.dart';
import '../../domain/entities/liveness_gate.dart';
import '../../domain/failures/liveness_failure.dart';
import 'liveness_flow_event.dart';
import 'liveness_flow_state.dart';

/// Pure `(State, Event) → State` state machine for the 5-gate flow.
///
/// No streams, no timers, no I/O. Timestamps and frame analysis results arrive
/// as events from the outside world. A side-effect-free function is trivial to
/// unit-test (see `test/features/face_liveness/application/flow/liveness_flow_machine_test.dart`)
/// and trivial to port to Swift / Kotlin by hand.
class LivenessFlowMachine {
  const LivenessFlowMachine();

  LivenessFlowState reduce(LivenessFlowState state, LivenessFlowEvent event) {
    return switch ((state, event)) {
      // Idle / Done / Failed → Initializing
      (FlowIdle _, StartRequested _) => const FlowInitializing(),
      (FlowDone _, StartRequested _) => const FlowInitializing(),
      (FlowFailed _, StartRequested _) => const FlowInitializing(),

      // Initializing → first gate
      (FlowInitializing _, InitializationCompleted _) => FlowEvaluating(
          gate: LivenessGate.orderedPipeline.first,
          consecutivePasses: 0,
        ),

      (FlowInitializing _, InitializationFailed e) =>
        FlowFailed(reason: e.reason, retryable: e.reason.isRetryable),

      // Evaluating: pipeline outcome for the current gate
      (FlowEvaluating current, FrameAnalyzed e) =>
        _reduceFrameAnalyzed(current, e),

      // Evaluating: timeout
      (FlowEvaluating _, TimeoutElapsed _) =>
        const FlowFailed(reason: LivenessFailure.timeout, retryable: true),

      // Capturing → Done / Failed
      (FlowCapturing _, CaptureComplete e) => FlowDone(e.photoPath, faceScore: e.faceScore),
      (FlowCapturing _, CaptureFailed e) =>
        FlowFailed(reason: e.reason, retryable: true),

      // Retry from any failed state goes back to Initializing.
      (FlowFailed f, UserRetry _) when f.retryable => const FlowInitializing(),

      // Anything else: no transition.
      _ => state,
    };
  }

  LivenessFlowState _reduceFrameAnalyzed(
    FlowEvaluating current,
    FrameAnalyzed event,
  ) {
    // Frame was evaluated against a different gate than we're currently on —
    // ignore it (likely in-flight result from a previous gate).
    if (event.outcome.evaluatedGate != current.gate) {
      return current;
    }

    if (event.outcome.didPass) {
      final nextCount = current.consecutivePasses + 1;
      if (nextCount >= AppConstants.debounceFrames) {
        return _advanceGate(current.gate);
      }
      return current.copyWith(
        consecutivePasses: nextCount,
        clearLastFailure: true,
      );
    }

    // Failed this frame: reset the debounce counter and surface the reason.
    return current.copyWith(
      consecutivePasses: 0,
      lastFailure: event.outcome.failure,
    );
  }

  LivenessFlowState _advanceGate(LivenessGate current) {
    final pipeline = LivenessGate.orderedPipeline;
    final idx = pipeline.indexOf(current);
    if (idx == -1 || idx == pipeline.length - 1) {
      return const FlowCapturing();
    }
    return FlowEvaluating(
      gate: pipeline[idx + 1],
      consecutivePasses: 0,
    );
  }
}

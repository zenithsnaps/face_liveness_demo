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

      // Evaluating → Capturing once the session has filled and the screen
      // is encoding the JPEGs (preview hidden, "verifying" banner shown).
      (FlowEvaluating _, BatchCaptureStarted _) => const FlowCapturing(),

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
      // Counter is now a pure UI hint — the transition to FlowCapturing is
      // owned by BatchCaptureStarted (dispatched from BatchCaptureCoordinator
      // once the 5-frame batch evaluates to a winner).
      return current.copyWith(
        consecutivePasses: current.consecutivePasses + 1,
        clearLastFailure: true,
      );
    }

    // Failed this frame: reset the debounce counter and surface the reason.
    return current.copyWith(
      consecutivePasses: 0,
      lastFailure: event.outcome.failure,
    );
  }
}

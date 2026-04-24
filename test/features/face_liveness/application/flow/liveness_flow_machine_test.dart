import 'package:face_liveness_demo/core/app_constants.dart';
import 'package:face_liveness_demo/core/result.dart';
import 'package:face_liveness_demo/features/face_liveness/application/flow/liveness_flow_event.dart';
import 'package:face_liveness_demo/features/face_liveness/application/flow/liveness_flow_machine.dart';
import 'package:face_liveness_demo/features/face_liveness/application/flow/liveness_flow_state.dart';
import 'package:face_liveness_demo/features/face_liveness/application/usecases/run_pipeline.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/liveness_gate.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:flutter_test/flutter_test.dart';

PipelineFrameOutcome pass(LivenessGate gate) => PipelineFrameOutcome(
      evaluatedGate: gate,
      result: const Ok(null),
    );

PipelineFrameOutcome fail(LivenessGate gate, LivenessFailure reason) =>
    PipelineFrameOutcome(
      evaluatedGate: gate,
      result: Err(reason),
    );

void main() {
  const machine = LivenessFlowMachine();

  group('initialization', () {
    test('FlowIdle + StartRequested → FlowInitializing', () {
      expect(
        machine.reduce(const FlowIdle(), const StartRequested()),
        const FlowInitializing(),
      );
    });

    test('FlowInitializing + InitializationCompleted → first gate', () {
      final next = machine.reduce(
        const FlowInitializing(),
        const InitializationCompleted(),
      );
      expect(next, isA<FlowEvaluating>());
      expect((next as FlowEvaluating).gate, LivenessGate.faceQuality);
      expect(next.consecutivePasses, 0);
    });

    test('FlowInitializing + InitializationFailed → FlowFailed', () {
      final next = machine.reduce(
        const FlowInitializing(),
        const InitializationFailed(LivenessFailure.cameraError),
      );
      expect(next, isA<FlowFailed>());
      expect((next as FlowFailed).reason, LivenessFailure.cameraError);
      expect(next.retryable, isTrue);
    });
  });

  group('debounce and advance', () {
    test('${AppConstants.debounceFrames} consecutive passes on the only gate → FlowCapturing', () {
      LivenessFlowState state = FlowEvaluating(
        gate: LivenessGate.faceQuality,
        consecutivePasses: 0,
      );
      for (var i = 0; i < AppConstants.debounceFrames; i++) {
        state = machine.reduce(
          state,
          FrameAnalyzed(pass(LivenessGate.faceQuality)),
        );
      }
      expect(state, isA<FlowCapturing>());
    });

    test('a failure resets consecutivePasses and surfaces lastFailure', () {
      var state = FlowEvaluating(
        gate: LivenessGate.faceQuality,
        consecutivePasses: 3,
      );
      state = machine.reduce(
            state,
            FrameAnalyzed(fail(LivenessGate.faceQuality, LivenessFailure.faceTooSmall)),
          )
          as FlowEvaluating;
      expect(state.consecutivePasses, 0);
      expect(state.lastFailure, LivenessFailure.faceTooSmall);
    });

    test('a pass clears lastFailure hint', () {
      var state = FlowEvaluating(
        gate: LivenessGate.faceQuality,
        consecutivePasses: 0,
        lastFailure: LivenessFailure.faceTooSmall,
      );
      state = machine.reduce(
            state,
            FrameAnalyzed(pass(LivenessGate.faceQuality)),
          )
          as FlowEvaluating;
      expect(state.lastFailure, isNull);
      expect(state.consecutivePasses, 1);
    });

    test('frame evaluated against a stale gate is ignored', () {
      final state = FlowEvaluating(
        gate: LivenessGate.livenessSmile,
        consecutivePasses: 2,
      );
      final next = machine.reduce(
        state,
        FrameAnalyzed(pass(LivenessGate.faceQuality)),
      );
      expect(next, state);
    });
  });

  group('end of pipeline', () {
    test('passing the final gate → FlowCapturing', () {
      var state = FlowEvaluating(
        gate: LivenessGate.livenessBlink,
        consecutivePasses: AppConstants.debounceFrames - 1,
      );
      final next = machine.reduce(
        state,
        FrameAnalyzed(pass(LivenessGate.livenessBlink)),
      );
      expect(next, const FlowCapturing());
    });

    test('FlowCapturing + CaptureComplete → FlowDone', () {
      final next = machine.reduce(
        const FlowCapturing(),
        const CaptureComplete('/tmp/photo.jpg', faceScore: 0.98),
      );
      expect(next, const FlowDone('/tmp/photo.jpg', faceScore: 0.98));
    });

    test('FlowCapturing + CaptureFailed → FlowFailed', () {
      final next = machine.reduce(
        const FlowCapturing(),
        const CaptureFailed(LivenessFailure.cameraError),
      );
      expect(next, isA<FlowFailed>());
    });
  });

  group('timeout and retry', () {
    test('timeout during evaluation → FlowFailed(timeout)', () {
      final next = machine.reduce(
        FlowEvaluating(gate: LivenessGate.livenessSmile, consecutivePasses: 1),
        const TimeoutElapsed(),
      );
      expect(next, isA<FlowFailed>());
      expect((next as FlowFailed).reason, LivenessFailure.timeout);
    });

    test('UserRetry from retryable failure → FlowInitializing', () {
      final next = machine.reduce(
        const FlowFailed(reason: LivenessFailure.timeout, retryable: true),
        const UserRetry(),
      );
      expect(next, const FlowInitializing());
    });

    test('UserRetry from non-retryable failure stays put', () {
      const state = FlowFailed(reason: LivenessFailure.cameraError, retryable: false);
      final next = machine.reduce(state, const UserRetry());
      expect(next, state);
    });
  });

  test('reduce is deterministic: same (state, event) always yields same result', () {
    final s1 = machine.reduce(const FlowIdle(), const StartRequested());
    final s2 = machine.reduce(const FlowIdle(), const StartRequested());
    expect(s1, s2);
  });
}

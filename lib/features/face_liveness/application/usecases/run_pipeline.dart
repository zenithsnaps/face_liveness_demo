import 'package:meta/meta.dart';

import '../../../../core/result.dart';
import '../../domain/entities/face_snapshot.dart';
import '../../domain/entities/frame_metadata.dart';
import '../../domain/entities/hand_snapshot.dart';
import '../../domain/entities/liveness_gate.dart';
import '../../domain/entities/object_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/value_objects/rect2d.dart';
import 'check_face_quality.dart';
import 'check_liveness_blink.dart';
import 'check_liveness_smile.dart';

/// Result of evaluating the gate that the flow machine currently cares about
/// against a single analyzed frame.
@immutable
class PipelineFrameOutcome {
  final LivenessGate evaluatedGate;
  final Result<void, LivenessFailure> result;

  const PipelineFrameOutcome({
    required this.evaluatedGate,
    required this.result,
  });

  bool get didPass => result.isOk;
  LivenessFailure? get failure => result.errOrNull;
}

/// Container for everything the pipeline needs to evaluate a single frame.
@immutable
class PipelineFrameInput {
  final FaceSnapshot? face;
  final List<HandSnapshot> hands;
  final List<ObjectSnapshot> objects;
  final Rect2D ovalGuide;
  final FrameMetadata frame;

  const PipelineFrameInput({
    required this.face,
    required this.hands,
    required this.objects,
    required this.ovalGuide,
    required this.frame,
  });
}

/// Composes individual use cases. Stateful for the liveness challenges
/// (smile / blink), which must observe across frames.
class RunPipeline {
  final CheckFaceQuality _faceQuality;
  final CheckLivenessSmile _smile;
  final CheckLivenessBlink _blink;

  RunPipeline({
    CheckFaceQuality? faceQuality,
    CheckLivenessSmile? smile,
    CheckLivenessBlink? blink,
  })  : _faceQuality = faceQuality ?? const CheckFaceQuality(),
        _smile = smile ?? CheckLivenessSmile(),
        _blink = blink ?? CheckLivenessBlink();

  void resetLivenessChallenges() {
    _smile.reset();
    _blink.reset();
  }

  PipelineFrameOutcome evaluate(LivenessGate gate, PipelineFrameInput input) {
    final face = input.face;

    // Every gate past faceQuality needs a face to work with; if none, short-circuit.
    if (gate != LivenessGate.faceQuality && face == null) {
      return PipelineFrameOutcome(
        evaluatedGate: gate,
        result: const Err(LivenessFailure.noFace),
      );
    }

    return switch (gate) {
      LivenessGate.faceQuality => PipelineFrameOutcome(
          evaluatedGate: gate,
          result: _faceQuality(
            face: face,
            ovalGuide: input.ovalGuide,
            frame: input.frame,
          ),
        ),
      LivenessGate.livenessSmile => PipelineFrameOutcome(
          evaluatedGate: gate,
          result: _smile.observe(face!).fold(
                (_) => const Ok(null),
                (err) => Err<void, LivenessFailure>(err),
              ),
        ),
      LivenessGate.livenessBlink => PipelineFrameOutcome(
          evaluatedGate: gate,
          result: _blink.observe(face!).fold(
                (_) => const Ok(null),
                (err) => Err<void, LivenessFailure>(err),
              ),
        ),
    };
  }
}

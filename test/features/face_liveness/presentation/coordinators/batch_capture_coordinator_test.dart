import 'package:face_liveness_demo/features/face_liveness/application/batch/score_frame.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_metadata.dart';
import 'package:face_liveness_demo/features/face_liveness/presentation/coordinators/batch_capture_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory encoder that hands out a unique fake path per call.
class _FakeEncoder {
  int _counter = 0;
  bool fail = false;

  Future<String?> call(FrameData frame) async {
    if (fail) return null;
    _counter++;
    return '/tmp/fake_frame_$_counter.jpg';
  }
}

ScoreFrame _frame({
  required double face,
  double hand = 0.0,
  int handCount = 0,
  double sun = 0.0,
  int tag = 0,
}) {
  return ScoreFrame(
    faceScore: face,
    handScore: hand,
    handCount: handCount,
    sunglassesScore: sun,
    eyeEvidence: null,
    frame: FrameData(
      bytes: const [],
      metadata: FrameMetadata(
        width: 1,
        height: 1,
        rotationDegrees: 0,
        format: FramePixelFormat.rgba8888,
        timestampMicros: tag,
      ),
    ),
  );
}

void main() {
  test('reports InProgress until target size reached', () async {
    final coord = BatchCaptureCoordinator(encoder: _FakeEncoder().call);
    final r1 = await coord.admit(_frame(face: 0.5), 3);
    final r2 = await coord.admit(_frame(face: 0.6), 3);
    expect(r1, isA<BatchAdmitInProgress>());
    expect(r2, isA<BatchAdmitInProgress>());
    expect((r2 as BatchAdmitInProgress).admittedCount, 2);
  });

  test('on the Nth admit, emits SessionComplete with all frames', () async {
    final coord = BatchCaptureCoordinator(encoder: _FakeEncoder().call);
    await coord.admit(_frame(face: 0.5, tag: 1), 3);
    await coord.admit(_frame(face: 0.9, tag: 2), 3);
    final last = await coord.admit(_frame(face: 0.7, tag: 3), 3);
    expect(last, isA<BatchSessionComplete>());
    final session = (last as BatchSessionComplete).session;
    expect(session.frames, hasLength(3));
    expect(session.faceMaxFrame.score.faceScore, 0.9);
    expect(session.faceMaxFrame.score.frame.timestampMicros, 2);
    for (var i = 0; i < session.frames.length; i++) {
      expect(session.frames[i].sequence, i + 1);
    }
    expect(session.groupId, isNotEmpty);
  });

  test('encoder failure → frame is skipped, count does not advance', () async {
    final encoder = _FakeEncoder()..fail = true;
    final coord = BatchCaptureCoordinator(encoder: encoder.call);
    final r = await coord.admit(_frame(face: 0.8), 2);
    expect(r, isA<BatchAdmitInProgress>());
    expect((r as BatchAdmitInProgress).admittedCount, 0);
  });

  test('reset() clears running session', () async {
    final coord = BatchCaptureCoordinator(encoder: _FakeEncoder().call);
    await coord.admit(_frame(face: 0.6), 5);
    await coord.admit(_frame(face: 0.9), 5);
    coord.reset();
    expect(coord.admittedCount, 0);
    expect(coord.groupId, isNull);
    final r = await coord.admit(_frame(face: 0.5), 5);
    expect((r as BatchAdmitInProgress).admittedCount, 1);
  });

  test('session resets after completion — next admit starts a fresh batch',
      () async {
    final coord = BatchCaptureCoordinator(encoder: _FakeEncoder().call);
    await coord.admit(_frame(face: 0.6), 2);
    await coord.admit(_frame(face: 0.9), 2);
    expect(coord.admittedCount, 0);
    final r = await coord.admit(_frame(face: 0.7), 2);
    expect(r, isA<BatchAdmitInProgress>());
    expect((r as BatchAdmitInProgress).admittedCount, 1);
  });
}

import 'package:face_liveness_demo/features/face_liveness/application/usecases/check_face_quality.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_metadata.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../mocks/face_snapshot_fixture.dart';

void main() {
  const usecase = CheckFaceQuality();
  final frame = FrameMetadata(
    width: 480,
    height: 640,
    rotationDegrees: 0,
    format: FramePixelFormat.yuv420,
    timestampMicros: 0,
  );

  group('CheckFaceQuality — bbox ratio', () {
    test('face at 79% width → faceTooSmall', () {
      final result = usecase(
        face: buildFaceSnapshot(widthRatio: 0.79),
        ovalGuide: defaultOvalGuide(),
        frame: frame,
      );
      expect(result.errOrNull, LivenessFailure.faceTooSmall);
    });

    test('face at 80% width → still faceTooSmall (below 90% target)', () {
      final result = usecase(
        face: buildFaceSnapshot(widthRatio: 0.80),
        ovalGuide: defaultOvalGuide(),
        frame: frame,
      );
      expect(result.errOrNull, LivenessFailure.faceTooSmall);
    });

    test('face at 90% width → passes', () {
      final result = usecase(
        face: buildFaceSnapshot(widthRatio: 0.90),
        ovalGuide: defaultOvalGuide(),
        frame: frame,
      );
      expect(result.isOk, isTrue);
    });

    test('face at 98% width → passes (boundary)', () {
      final result = usecase(
        face: buildFaceSnapshot(widthRatio: 0.98),
        ovalGuide: defaultOvalGuide(),
        frame: frame,
      );
      expect(result.isOk, isTrue);
    });

    test('face at 99% width → faceTooLarge', () {
      final result = usecase(
        face: buildFaceSnapshot(widthRatio: 0.99),
        ovalGuide: defaultOvalGuide(),
        frame: frame,
      );
      expect(result.errOrNull, LivenessFailure.faceTooLarge);
    });
  });

  group('CheckFaceQuality — missing / pose / eyes', () {
    test('no face → noFace', () {
      final result = usecase(
        face: null,
        ovalGuide: defaultOvalGuide(),
        frame: frame,
      );
      expect(result.errOrNull, LivenessFailure.noFace);
    });

    test('yaw > 15° → headPoseOff', () {
      final result = usecase(
        face: buildFaceSnapshot(yaw: 20),
        ovalGuide: defaultOvalGuide(),
        frame: frame,
      );
      expect(result.errOrNull, LivenessFailure.headPoseOff);
    });

    test('eyes closed → eyesClosed', () {
      final result = usecase(
        face: buildFaceSnapshot(leftEye: 0.2, rightEye: 0.2),
        ovalGuide: defaultOvalGuide(),
        frame: frame,
      );
      expect(result.errOrNull, LivenessFailure.eyesClosed);
    });
  });
}

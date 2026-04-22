import 'package:face_liveness_demo/features/face_liveness/application/usecases/check_no_object_occlusion.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/face_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/object_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/confidence.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/rect2d.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../mocks/face_snapshot_fixture.dart';

void main() {
  const usecase = CheckNoObjectOcclusion();

  test('no objects → Ok', () {
    final result = usecase(face: buildFaceSnapshot(), objects: []);
    expect(result.isOk, isTrue);
  });

  test('object far from face → Ok', () {
    final face = buildFaceSnapshot();
    final obj = ObjectSnapshot(
      boundingBox: const Rect2D.fromLTWH(1000, 1000, 50, 50),
      label: 'cell phone',
      confidence: const Confidence(0.9),
    );
    final result = usecase(face: face, objects: [obj]);
    expect(result.isOk, isTrue);
  });

  test('object overlapping face bbox → objectOccluding', () {
    final face = buildFaceSnapshot();
    // a phone directly over the face
    final obj = ObjectSnapshot(
      boundingBox: Rect2D.fromLTWH(
        face.boundingBox.left + 10,
        face.boundingBox.top + 10,
        face.boundingBox.width - 20,
        face.boundingBox.height / 2,
      ),
      label: 'cell phone',
      confidence: const Confidence(0.9),
    );
    final result = usecase(face: face, objects: [obj]);
    expect(result.errOrNull, LivenessFailure.objectOccluding);
  });

  test('mouth landmark visibility below threshold → objectOccluding', () {
    final face = buildFaceSnapshot(
      landmarkVisibility: const {
        FaceLandmarkType.mouthLeft: Confidence(0.4),
      },
    );
    final result = usecase(face: face, objects: []);
    expect(result.errOrNull, LivenessFailure.objectOccluding);
  });

  test('all critical landmarks visible → Ok', () {
    final face = buildFaceSnapshot(
      landmarkVisibility: const {
        FaceLandmarkType.noseBase: Confidence(0.95),
        FaceLandmarkType.mouthLeft: Confidence(0.95),
        FaceLandmarkType.mouthRight: Confidence(0.95),
        FaceLandmarkType.mouthBottom: Confidence(0.95),
      },
    );
    final result = usecase(face: face, objects: []);
    expect(result.isOk, isTrue);
  });
}

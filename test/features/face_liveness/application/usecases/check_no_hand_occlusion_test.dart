import 'package:face_liveness_demo/features/face_liveness/application/usecases/check_no_hand_occlusion.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/hand_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/confidence.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/point2d.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../mocks/face_snapshot_fixture.dart';

HandSnapshot handWithFingertipAt(Point2D p) {
  // Build 21 landmarks; put all fingertips at the given point, palm/wrist far away.
  final landmarks = List<Point2D>.generate(21, (_) => const Point2D(-1000, -1000));
  for (final i in [4, 8, 12, 16, 20]) {
    landmarks[i] = p;
  }
  return HandSnapshot(
    landmarks: landmarks,
    confidence: const Confidence(0.9),
    handedness: Handedness.right,
  );
}

HandSnapshot handFarAway() {
  final landmarks = List<Point2D>.generate(21, (_) => const Point2D(-1000, -1000));
  return HandSnapshot(
    landmarks: landmarks,
    confidence: const Confidence(0.9),
    handedness: Handedness.left,
  );
}

void main() {
  const usecase = CheckNoHandOcclusion();

  test('no hands → Ok', () {
    final result = usecase(face: buildFaceSnapshot(), hands: []);
    expect(result.isOk, isTrue);
  });

  test('hand fully off-frame → Ok', () {
    final result = usecase(face: buildFaceSnapshot(), hands: [handFarAway()]);
    expect(result.isOk, isTrue);
  });

  test('fingertip inside face bbox → handOccluding', () {
    final face = buildFaceSnapshot();
    final fingertip = face.boundingBox.center; // dead center of the face
    final result = usecase(
      face: face,
      hands: [handWithFingertipAt(fingertip)],
    );
    expect(result.errOrNull, LivenessFailure.handOccluding);
  });

  test('fingertip in 15% expansion halo → handOccluding', () {
    final face = buildFaceSnapshot();
    final expanded = face.boundingBox.expanded(0.15);
    // pick a point between the face bbox and the expansion boundary
    final haloPoint = Point2D(
      face.boundingBox.right + (expanded.right - face.boundingBox.right) / 2,
      face.boundingBox.center.y,
    );
    final result = usecase(
      face: face,
      hands: [handWithFingertipAt(haloPoint)],
    );
    expect(result.errOrNull, LivenessFailure.handOccluding);
  });

  test('landmark outside expansion → Ok', () {
    final face = buildFaceSnapshot();
    final expanded = face.boundingBox.expanded(0.15);
    final outside = Point2D(expanded.right + 50, face.boundingBox.center.y);
    final result = usecase(
      face: face,
      hands: [handWithFingertipAt(outside)],
    );
    expect(result.isOk, isTrue);
  });
}

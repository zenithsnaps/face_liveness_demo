import '../../../../core/app_constants.dart';
import '../../../../core/result.dart';
import '../../domain/entities/face_snapshot.dart';
import '../../domain/entities/hand_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';

/// Gate 4 — no hand or finger is blocking the face.
///
/// For each detected hand, check if ANY landmark (especially the 5 fingertips)
/// lies inside the face bbox expanded by [AppConstants.faceBboxExpansionForHand].
/// Per spec §4.
class CheckNoHandOcclusion {
  const CheckNoHandOcclusion();

  Result<void, LivenessFailure> call({
    required FaceSnapshot face,
    required List<HandSnapshot> hands,
  }) {
    final confident = hands
        .where((h) => h.confidence.value >= AppConstants.handDetectionMinConfidence)
        .toList();
    if (confident.isEmpty) return const Ok(null);

    final expanded = face.boundingBox.expanded(AppConstants.faceBboxExpansionForHand);

    for (final hand in confident) {
      // First check fingertips (fast path + highest signal).
      for (final idx in AppConstants.fingertipLandmarkIndices) {
        if (idx < hand.landmarks.length &&
            expanded.contains(hand.landmarks[idx])) {
          return const Err(LivenessFailure.handOccluding);
        }
      }
      // Then any other landmark — catches palm-over-face cases.
      for (final point in hand.landmarks) {
        if (expanded.contains(point)) {
          return const Err(LivenessFailure.handOccluding);
        }
      }
    }

    return const Ok(null);
  }
}

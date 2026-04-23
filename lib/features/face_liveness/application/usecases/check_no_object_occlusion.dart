import '../../../../core/app_constants.dart';
import '../../../../core/result.dart';
import '../../domain/entities/face_snapshot.dart';
import '../../domain/entities/object_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';

/// Gate 3 — no object is blocking the face.
///
/// Two complementary signals (spec §3):
///  1. Object detector bbox overlapping the face bbox by more than a small
///     fraction of the object's own area.
///  2. Face landmark visibility scores in nose / mouth regions dropping below
///     [AppConstants.landmarkVisibilityThreshold].
class CheckNoObjectOcclusion {
  const CheckNoObjectOcclusion();

  Result<void, LivenessFailure> call({
    required FaceSnapshot face,
    required List<ObjectSnapshot> objects,
    double? landmarkVisibilityThreshold,
  }) {
    // Signal 1 — detected object overlapping the face.
    // Exclude low-confidence detections and labels that are never real occlusions.
    for (final obj in objects) {
      if (obj.confidence.value < AppConstants.objectDetectionMinConfidence) {
        continue;
      }
      if (AppConstants.objectOcclusionExcludedLabels
          .contains(obj.label.toLowerCase())) {
        continue;
      }
      if (_overlapsFace(face, obj)) {
        return const Err(LivenessFailure.objectOccluding);
      }
    }

    // Signal 2 — critical landmark visibility drop.
    final visibility = face.landmarkVisibility;
    if (visibility.isNotEmpty) {
      const critical = [
        FaceLandmarkType.noseBase,
        FaceLandmarkType.mouthLeft,
        FaceLandmarkType.mouthRight,
        FaceLandmarkType.mouthBottom,
      ];
      for (final key in critical) {
        final v = visibility[key];
        final visThreshold =
            landmarkVisibilityThreshold ?? AppConstants.landmarkVisibilityThreshold;
        if (v != null && v.value < visThreshold) {
          return const Err(LivenessFailure.objectOccluding);
        }
      }
    }

    return const Ok(null);
  }

  bool _overlapsFace(FaceSnapshot face, ObjectSnapshot obj) {
    final fraction = face.boundingBox.overlapFractionOf(obj.boundingBox);
    return fraction > AppConstants.objectBboxOverlapThreshold;
  }
}

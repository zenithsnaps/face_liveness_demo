import 'dart:math' as math;

import '../../../../core/app_constants.dart';
import '../../../../core/result.dart';
import '../../domain/entities/face_snapshot.dart';
import '../../domain/entities/frame_metadata.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/value_objects/rect2d.dart';

/// Gate 2 — face fills the oval guide, head is roughly straight, eyes open.
///
/// Takes the detected face and the oval guide rect (in frame pixel space)
/// and returns either `Ok(unit)` or `Err(LivenessFailure)`.
class CheckFaceQuality {
  const CheckFaceQuality();

  Result<void, LivenessFailure> call({
    required FaceSnapshot? face,
    required Rect2D ovalGuide,
    required FrameMetadata frame,
  }) {
    if (face == null) {
      return const Err(LivenessFailure.noFace);
    }

    final faceWidthRatio = face.boundingBox.width / ovalGuide.width;

    if (faceWidthRatio < AppConstants.faceBboxMinRatio) {
      return const Err(LivenessFailure.faceTooSmall);
    }
    if (faceWidthRatio > AppConstants.faceBboxMaxRatio) {
      return const Err(LivenessFailure.faceTooLarge);
    }
    // Must actually fill (>= 90%) to pass — 80..90% is "keep moving closer".
    if (faceWidthRatio < AppConstants.faceBboxTargetRatio) {
      return const Err(LivenessFailure.faceTooSmall);
    }

    // Center of face must lie inside the oval guide.
    if (!ovalGuide.contains(face.boundingBox.center)) {
      return const Err(LivenessFailure.faceOffCenter);
    }

    // Head pose straight.
    final yaw = face.headPose.yaw.abs();
    final pitch = face.headPose.pitch.abs();
    final roll = face.headPose.roll.abs();
    if (yaw > AppConstants.headPoseMaxYawDegrees ||
        pitch > AppConstants.headPoseMaxPitchDegrees ||
        roll > AppConstants.headPoseMaxRollDegrees) {
      return const Err(LivenessFailure.headPoseOff);
    }

    // Both eyes reasonably open (so we don't accidentally treat a blink as
    // "not looking"). Use a mild threshold — blink detection is Gate 1b.
    final minEyeOpen = math.min(
      face.leftEyeOpenProbability.value,
      face.rightEyeOpenProbability.value,
    );
    if (minEyeOpen < 0.5) {
      return const Err(LivenessFailure.eyesClosed);
    }

    return const Ok(null);
  }
}

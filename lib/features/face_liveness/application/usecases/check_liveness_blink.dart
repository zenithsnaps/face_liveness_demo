import '../../../../core/app_constants.dart';
import '../../../../core/result.dart';
import '../../domain/entities/face_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';

/// Gate 1b — blink challenge.
///
/// Passes when BOTH eyes' open-probability drop below
/// [AppConstants.eyeClosedThreshold] and then rise above
/// [AppConstants.eyeOpenThreshold] within the same observation window.
class CheckLivenessBlink {
  bool _sawClosed = false;
  bool _passed = false;

  bool get hasPassed => _passed;

  void reset() {
    _sawClosed = false;
    _passed = false;
  }

  Result<bool, LivenessFailure> observe(FaceSnapshot face) {
    final l = face.leftEyeOpenProbability.value;
    final r = face.rightEyeOpenProbability.value;

    if (l < AppConstants.eyeClosedThreshold &&
        r < AppConstants.eyeClosedThreshold) {
      _sawClosed = true;
    }
    if (_sawClosed &&
        l > AppConstants.eyeOpenThreshold &&
        r > AppConstants.eyeOpenThreshold) {
      _passed = true;
    }
    if (_passed) {
      return const Ok(true);
    }
    return const Err(LivenessFailure.blinkNotDetected);
  }
}

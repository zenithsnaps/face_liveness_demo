import '../../../../core/app_constants.dart';
import '../../../../core/result.dart';
import '../../domain/entities/face_snapshot.dart';
import '../../domain/failures/liveness_failure.dart';

/// Gate 1a — smile challenge.
///
/// Passes once we've observed `smilingProbability` crossing from below
/// [AppConstants.smileLowThreshold] up through [AppConstants.smileHighThreshold]
/// within a tracked sequence of frames. Stateful: call [observe] per frame;
/// the caller holds onto the instance.
class CheckLivenessSmile {
  bool _sawLow = false;
  bool _passed = false;

  bool get hasPassed => _passed;

  void reset() {
    _sawLow = false;
    _passed = false;
  }

  Result<bool, LivenessFailure> observe(FaceSnapshot face) {
    final p = face.smilingProbability.value;
    if (p < AppConstants.smileLowThreshold) {
      _sawLow = true;
    }
    if (_sawLow && p > AppConstants.smileHighThreshold) {
      _passed = true;
    }
    if (_passed) {
      return const Ok(true);
    }
    return const Err(LivenessFailure.smileNotDetected);
  }
}

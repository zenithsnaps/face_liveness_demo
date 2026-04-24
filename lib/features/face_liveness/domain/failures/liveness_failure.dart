import '../../../../core/app_strings.dart';

enum LivenessFailure {
  noFace,
  multipleFaces,
  faceTooSmall,
  faceTooLarge,
  faceOffCenter,
  headPoseOff,
  eyesNotVisible,
  eyesClosed,
  smileNotDetected,
  blinkNotDetected,
  objectOccluding,
  eyeOccluded,
  handOccluding,
  cameraError,
  analyzerError,
  timeout,
}

extension LivenessFailureMessage on LivenessFailure {
  String get thaiMessage => switch (this) {
        LivenessFailure.noFace => AppStrings.noFaceDetected,
        LivenessFailure.multipleFaces => AppStrings.multipleFaces,
        LivenessFailure.faceTooSmall => AppStrings.moveCloser,
        LivenessFailure.faceTooLarge => AppStrings.moveFarther,
        LivenessFailure.faceOffCenter => AppStrings.frameYourFace,
        LivenessFailure.headPoseOff => AppStrings.lookStraight,
        LivenessFailure.eyesNotVisible => AppStrings.eyesNotVisible,
        LivenessFailure.eyesClosed => AppStrings.openEyes,
        LivenessFailure.smileNotDetected => AppStrings.pleaseSmile,
        LivenessFailure.blinkNotDetected => AppStrings.pleaseBlink,
        LivenessFailure.objectOccluding => AppStrings.objectCoveringFace,
        LivenessFailure.eyeOccluded => AppStrings.eyeOccluded,
        LivenessFailure.handOccluding => AppStrings.handCoveringFace,
        LivenessFailure.cameraError => 'กล้องทำงานผิดปกติ',
        LivenessFailure.analyzerError => 'ไม่สามารถวิเคราะห์ภาพได้',
        LivenessFailure.timeout => 'หมดเวลา กรุณาลองใหม่',
      };

  bool get isRetryable => switch (this) {
        LivenessFailure.cameraError => true,
        LivenessFailure.analyzerError => true,
        _ => true, // user can always retry positioning
      };
}

/// Error type returned from analyzer repositories.
class AnalyzerError {
  final String message;
  final Object? cause;

  const AnalyzerError(this.message, {this.cause});

  @override
  String toString() => 'AnalyzerError($message${cause != null ? ', cause=$cause' : ''})';
}

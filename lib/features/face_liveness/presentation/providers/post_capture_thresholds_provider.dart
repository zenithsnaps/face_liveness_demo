import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/usecases/post_capture_thresholds.dart';

class PostCaptureThresholdsController
    extends Notifier<PostCaptureThresholds> {
  @override
  PostCaptureThresholds build() => PostCaptureThresholds.defaults;

  void setFaceScore(double v) => state = state.copyWith(faceScore: v);
  void setHandConfidence(double v) => state = state.copyWith(handConfidence: v);
  void setLandmarkVisibility(double v) =>
      state = state.copyWith(landmarkVisibility: v);
  void setGlassesThreshold(double v) =>
      state = state.copyWith(glassesThreshold: v);
}

final postCaptureThresholdsProvider = NotifierProvider<
    PostCaptureThresholdsController, PostCaptureThresholds>(
  PostCaptureThresholdsController.new,
);

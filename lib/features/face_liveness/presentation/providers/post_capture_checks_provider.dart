import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/usecases/post_capture_checks.dart';

class PostCaptureChecksController extends Notifier<PostCaptureChecks> {
  @override
  PostCaptureChecks build() => PostCaptureChecks.defaults;

  void setFaceEnabled(bool v) => state = state.copyWith(faceEnabled: v);
  void setHandEnabled(bool v) => state = state.copyWith(handEnabled: v);
}

final postCaptureChecksProvider =
    NotifierProvider<PostCaptureChecksController, PostCaptureChecks>(
  PostCaptureChecksController.new,
);

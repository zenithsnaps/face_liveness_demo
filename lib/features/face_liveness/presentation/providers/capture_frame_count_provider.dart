import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_constants.dart';

/// Number of stream frames to collect per capture session, configurable on
/// the home screen via slider. Bounded by
/// [AppConstants.captureFrameCountMin] / [AppConstants.captureFrameCountMax].
class CaptureFrameCountController extends Notifier<int> {
  @override
  int build() => AppConstants.captureFrameCountDefault;

  void set(int n) {
    final clamped =
        n.clamp(AppConstants.captureFrameCountMin, AppConstants.captureFrameCountMax);
    state = clamped;
  }
}

final captureFrameCountProvider =
    NotifierProvider<CaptureFrameCountController, int>(
  CaptureFrameCountController.new,
);

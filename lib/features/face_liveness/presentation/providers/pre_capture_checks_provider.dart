import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/usecases/pre_capture_checks.dart';

class PreCaptureChecksController extends Notifier<PreCaptureChecks> {
  @override
  PreCaptureChecks build() => PreCaptureChecks.defaults;

  void setEyesEnabled(bool v) => state = state.copyWith(eyesEnabled: v);
}

final preCaptureChecksProvider =
    NotifierProvider<PreCaptureChecksController, PreCaptureChecks>(
  PreCaptureChecksController.new,
);

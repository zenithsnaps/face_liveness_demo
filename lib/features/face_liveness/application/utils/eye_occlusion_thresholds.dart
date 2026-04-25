import 'package:meta/meta.dart';

import '../../../../core/app_constants.dart';

/// Configurable thresholds for [EyeOcclusionUtil.detect].
///
/// All defaults come from [AppConstants]. Override individual fields
/// when tuning without changing global constants.
@immutable
class EyeOcclusionThresholds {
  final double lumRatioPass;
  final double lumRatioBlock;
  final double stdDevPass;
  final double stdDevBlock;
  final double saturationPass;
  final double saturationBlock;
  final double blockScore;

  const EyeOcclusionThresholds({
    this.lumRatioPass = AppConstants.eyeLumRatioPass,
    this.lumRatioBlock = AppConstants.eyeLumRatioBlock,
    this.stdDevPass = AppConstants.eyeStdDevPass,
    this.stdDevBlock = AppConstants.eyeStdDevBlock,
    this.saturationPass = AppConstants.eyeSaturationPass,
    this.saturationBlock = AppConstants.eyeSaturationBlock,
    this.blockScore = AppConstants.eyeOcclusionBlockScore,
  });

  static const defaults = EyeOcclusionThresholds();
}

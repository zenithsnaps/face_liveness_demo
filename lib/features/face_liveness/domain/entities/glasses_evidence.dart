import 'package:meta/meta.dart';

/// Output of the on-device sunglasses classifier.
///
/// Produced by a [GlassesClassifierAnalyzer]. The model is a tiny CNN
/// (TinyBinaryClassifier, ~27k params) ported from the `glasses-detector`
/// project, exported to TFLite with `/255` + ImageNet normalization +
/// `sigmoid` baked in — so [sunglassesProba] is already a probability in
/// `[0, 1]`, no post-processing required.
@immutable
class GlassesEvidence {
  /// P(face is wearing sunglasses), in `[0, 1]`.
  final double sunglassesProba;

  /// Decision threshold that was applied to [sunglassesProba].
  final double threshold;

  const GlassesEvidence({
    required this.sunglassesProba,
    required this.threshold,
  });

  bool get isWearingSunglasses => sunglassesProba >= threshold;

  static const empty = GlassesEvidence(sunglassesProba: 0, threshold: 1);

  @override
  String toString() =>
      'GlassesEvidence(proba=${sunglassesProba.toStringAsFixed(3)}, '
      'threshold=$threshold, sunglasses=$isWearingSunglasses)';
}

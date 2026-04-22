import 'package:meta/meta.dart';

/// A probability / confidence in [0, 1].
@immutable
class Confidence {
  final double value;

  const Confidence(this.value)
      : assert(value >= 0, 'confidence must be >= 0'),
        assert(value <= 1, 'confidence must be <= 1');

  const Confidence.zero() : value = 0;
  const Confidence.one() : value = 1;

  /// Safe factory that clamps out-of-range inputs — use when converting
  /// from external SDK scores where trust is lower.
  factory Confidence.clamped(double raw) {
    if (raw.isNaN) return const Confidence.zero();
    if (raw <= 0) return const Confidence.zero();
    if (raw >= 1) return const Confidence.one();
    return Confidence(raw);
  }

  bool get isAbove0p7 => value >= 0.7;
  bool get isBelow0p3 => value <= 0.3;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Confidence && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Confidence($value)';
}

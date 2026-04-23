import 'dart:math' as math;

double mean(Iterable<double> xs) {
  final list = xs.toList();
  if (list.isEmpty) return 0;
  return list.reduce((a, b) => a + b) / list.length;
}

double median(List<double> sortedXs) {
  if (sortedXs.isEmpty) return 0;
  final n = sortedXs.length;
  if (n.isOdd) return sortedXs[n ~/ 2];
  return (sortedXs[n ~/ 2 - 1] + sortedXs[n ~/ 2]) / 2;
}

double quantile(List<double> sortedXs, double q) {
  assert(q >= 0 && q <= 1);
  if (sortedXs.isEmpty) return 0;
  final idx = q * (sortedXs.length - 1);
  final lo = idx.floor();
  final hi = idx.ceil();
  if (lo == hi) return sortedXs[lo];
  return sortedXs[lo] + (sortedXs[hi] - sortedXs[lo]) * (idx - lo);
}

double passRateAtThreshold(Iterable<double> xs, double t) {
  final list = xs.toList();
  if (list.isEmpty) return 0;
  final passing = list.where((x) => x >= t).length;
  return passing / list.length;
}

/// Returns counts per bucket. bucket i covers [i*step, (i+1)*step).
/// The last bucket is inclusive on the right edge (score == 1.0 goes into the last bucket).
List<int> histogramBuckets(Iterable<double> xs, {int buckets = 20}) {
  final counts = List<int>.filled(buckets, 0);
  final step = 1.0 / buckets;
  for (final x in xs) {
    final idx = math.min((x / step).floor(), buckets - 1);
    counts[idx]++;
  }
  return counts;
}

({
  double min,
  double q1,
  double median,
  double q3,
  double max,
  double mean,
}) summarize(List<double> xs) {
  if (xs.isEmpty) {
    return (min: 0, q1: 0, median: 0, q3: 0, max: 0, mean: 0);
  }
  final sorted = [...xs]..sort();
  return (
    min: sorted.first,
    q1: quantile(sorted, 0.25),
    median: median(sorted),
    q3: quantile(sorted, 0.75),
    max: sorted.last,
    mean: mean(sorted),
  );
}

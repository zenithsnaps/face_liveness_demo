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

/// Returns density per bucket: count[i] / total. Values sum to 1.0.
List<double> densityBuckets(Iterable<double> xs, {int buckets = 20}) {
  final list = xs.toList();
  if (list.isEmpty) return List.filled(buckets, 0.0);
  final counts = histogramBuckets(list, buckets: buckets);
  final total = list.length;
  return counts.map((c) => c / total).toList();
}

/// FAR and FRR at a single threshold.
/// FRR = fraction of live scores that fall below t (live incorrectly rejected).
/// FAR = fraction of spoof scores that meet or exceed t (spoof incorrectly accepted).
({double far, double frr}) farFrrAt(
    List<double> live, List<double> spoof, double t) {
  final frr =
      live.isEmpty ? 0.0 : live.where((x) => x < t).length / live.length;
  final far =
      spoof.isEmpty ? 0.0 : spoof.where((x) => x >= t).length / spoof.length;
  return (far: far, frr: frr);
}

/// FAR/FRR curve sampled at [points] evenly-spaced thresholds from 0 to 1.
List<({double t, double far, double frr})> farFrrCurve(
  List<double> live,
  List<double> spoof, {
  int points = 101,
}) {
  return List.generate(points, (i) {
    final t = i / (points - 1);
    final r = farFrrAt(live, spoof, t);
    return (t: t, far: r.far, frr: r.frr);
  });
}

/// Returns the Equal Error Rate point (threshold where |FAR - FRR| is minimized).
({double threshold, double rate})? equalErrorRate(
    List<({double t, double far, double frr})> curve) {
  if (curve.isEmpty) return null;
  double bestDiff = double.infinity;
  ({double threshold, double rate})? best;
  for (final p in curve) {
    final diff = (p.far - p.frr).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = (threshold: p.t, rate: (p.far + p.frr) / 2);
    }
  }
  return best;
}

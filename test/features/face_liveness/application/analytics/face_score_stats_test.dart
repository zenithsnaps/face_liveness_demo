import 'package:face_liveness_demo/features/face_liveness/application/analytics/face_score_stats.dart'
    as stats;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mean', () {
    test('empty list returns 0', () => expect(stats.mean([]), 0));
    test('single value', () => expect(stats.mean([0.8]), 0.8));
    test('multiple values', () {
      expect(stats.mean([0.2, 0.4, 0.6, 0.8]), closeTo(0.5, 1e-10));
    });
  });

  group('median', () {
    test('empty list returns 0', () => expect(stats.median([]), 0));
    test('single value', () => expect(stats.median([0.7]), 0.7));
    test('odd count', () => expect(stats.median([0.1, 0.5, 0.9]), 0.5));
    test('even count', () {
      expect(stats.median([0.2, 0.4, 0.6, 0.8]), closeTo(0.5, 1e-10));
    });
  });

  group('quantile', () {
    test('q=0 returns min', () {
      expect(stats.quantile([0.1, 0.5, 0.9], 0), closeTo(0.1, 1e-10));
    });
    test('q=1 returns max', () {
      expect(stats.quantile([0.1, 0.5, 0.9], 1), closeTo(0.9, 1e-10));
    });
    test('q=0.5 returns median', () {
      expect(stats.quantile([0.0, 0.5, 1.0], 0.5), closeTo(0.5, 1e-10));
    });
    test('interpolates between indices', () {
      // sorted: [0, 0.5, 1.0]; idx for q=0.25 → 0.5 → floor=0, ceil=1
      // result = 0.0 + (0.5-0.0)*0.5 = 0.25
      expect(stats.quantile([0.0, 0.5, 1.0], 0.25), closeTo(0.25, 1e-10));
    });
  });

  group('passRateAtThreshold', () {
    test('empty list returns 0', () {
      expect(stats.passRateAtThreshold([], 0.9), 0);
    });
    test('t=0 everything passes', () {
      expect(stats.passRateAtThreshold([0.1, 0.5, 0.9], 0), 1.0);
    });
    test('t=1 only exact 1.0 passes', () {
      expect(stats.passRateAtThreshold([0.5, 0.9, 1.0], 1.0), closeTo(1 / 3, 1e-10));
    });
    test('partial pass', () {
      expect(stats.passRateAtThreshold([0.6, 0.8, 0.9, 1.0], 0.85),
          closeTo(0.5, 1e-10));
    });
  });

  group('histogramBuckets', () {
    test('empty list', () {
      final b = stats.histogramBuckets([], buckets: 20);
      expect(b, List.filled(20, 0));
    });
    test('value at 0.97 lands in bucket 19 (last)', () {
      // 0.97 * 20 = 19.4 → floor → 19. Avoids fp boundary at 0.95.
      final b = stats.histogramBuckets([0.97], buckets: 20);
      expect(b[19], 1);
      expect(b.take(19).every((c) => c == 0), isTrue);
    });
    test('value exactly 1.0 lands in bucket 19 (last)', () {
      final b = stats.histogramBuckets([1.0], buckets: 20);
      expect(b[19], 1);
    });
    test('values distributed correctly', () {
      final b = stats.histogramBuckets([0.0, 0.5, 0.99], buckets: 20);
      expect(b[0], 1);  // 0.0 → bucket 0 (0.00–0.05)
      expect(b[10], 1); // 0.5 → bucket 10 (0.50–0.55)
      expect(b[19], 1); // 0.99 → bucket 19
    });
  });

  group('summarize', () {
    test('empty list returns zeros', () {
      final s = stats.summarize([]);
      expect(s.min, 0);
      expect(s.max, 0);
      expect(s.mean, 0);
    });
    test('single value', () {
      final s = stats.summarize([0.75]);
      expect(s.min, 0.75);
      expect(s.max, 0.75);
      expect(s.mean, 0.75);
      expect(s.median, 0.75);
    });
    test('full summary is correct', () {
      // [0.2, 0.4, 0.6, 0.8] sorted
      final s = stats.summarize([0.6, 0.2, 0.8, 0.4]);
      expect(s.min, closeTo(0.2, 1e-10));
      expect(s.max, closeTo(0.8, 1e-10));
      expect(s.mean, closeTo(0.5, 1e-10));
      expect(s.median, closeTo(0.5, 1e-10));
      // quantile([0.2,0.4,0.6,0.8], 0.25): idx = 0.25*3 = 0.75
      // → 0.2 + 0.75*(0.4-0.2) = 0.35
      expect(s.q1, closeTo(0.35, 1e-10));
      // quantile([0.2,0.4,0.6,0.8], 0.75): idx = 0.75*3 = 2.25
      // → 0.6 + 0.25*(0.8-0.6) = 0.65
      expect(s.q3, closeTo(0.65, 1e-10));
    });
  });
}

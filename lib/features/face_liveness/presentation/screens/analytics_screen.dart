import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/analytics/face_score_stats.dart' as stats;
import '../providers/analytics_provider.dart';
import '../providers/test_cases_provider.dart';
import '../utils/share_png.dart';
import '../widgets/analytics/box_plot_per_case_chart.dart';
import '../widgets/analytics/confusion_matrix_card.dart';
import '../widgets/analytics/histogram_chart.dart';
import '../widgets/analytics/pass_rate_curve_chart.dart';
import '../widgets/analytics/test_case_label_editor.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  final _fullKey = GlobalKey();
  final _passRateKey = GlobalKey();
  final _histKey = GlobalKey();
  final _boxKey = GlobalKey();
  final _confKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final attemptsAsync = ref.watch(analyticsAttemptsProvider);
    final threshold = ref.watch(analyticsThresholdProvider);
    final filters = ref.watch(analyticsFiltersProvider);
    final allCases =
        ref.watch(testCasesListProvider).valueOrNull ?? const <String>[];
    final labels =
        ref.watch(testCaseLabelsProvider).valueOrNull ??
            const <String, TestCaseLabel>{};

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('วิเคราะห์ Face Score',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'แชร์ภาพรวม',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => sharePng(_fullKey, filename: 'analytics_full.png', context: context),
          ),
        ],
      ),
      body: attemptsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text('โหลดข้อมูลไม่สำเร็จ: $e',
                  style: const TextStyle(color: Colors.white54)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.invalidate(analyticsAttemptsProvider),
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
        data: (attempts) {
          final scores = attempts
              .where((a) => a.faceScore != null)
              .map((a) => a.faceScore!)
              .toList();
          final sorted = [...scores]..sort();
          final mean = stats.mean(scores);
          final med = stats.median(sorted);
          final passRate =
              stats.passRateAtThreshold(scores, threshold) * 100;

          // Group by test_case for box plot
          final groups = <String, List<double>>{};
          for (final a in attempts) {
            if (a.faceScore == null) continue;
            final key = a.testCase ?? '(ไม่ระบุ)';
            groups.putIfAbsent(key, () => []).add(a.faceScore!);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: RepaintBoundary(
              key: _fullKey,
              child: Container(
                color: const Color(0xFF121212),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Filter bar ──────────────────────────────────────
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: AnalyticsDateRange.values.map((r) {
                              final selected = filters.range == r;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ChoiceChip(
                                  label: Text(r.label),
                                  selected: selected,
                                  onSelected: (_) => ref
                                      .read(analyticsFiltersProvider.notifier)
                                      .setRange(r),
                                ),
                              );
                            }).toList(),
                          ),
                          if (allCases.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: allCases.map((c) {
                                final sel = filters.testCases.contains(c);
                                return FilterChip(
                                  label: Text(c,
                                      style: const TextStyle(fontSize: 11)),
                                  selected: sel,
                                  onSelected: (_) => ref
                                      .read(analyticsFiltersProvider.notifier)
                                      .toggleTestCase(c),
                                );
                              }).toList(),
                            ),
                            if (filters.testCases.isNotEmpty)
                              TextButton(
                                onPressed: () => ref
                                    .read(analyticsFiltersProvider.notifier)
                                    .clearTestCases(),
                                child: const Text('ล้าง filter'),
                              ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            '${attempts.length} attempts'
                            '${scores.isEmpty ? '' : '  •  ${scores.length} มี face_score'}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Threshold slider ─────────────────────────────────
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Threshold',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              const Spacer(),
                              Text(
                                '${(threshold * 100).toStringAsFixed(0)}%'
                                '  →  pass ${passRate.toStringAsFixed(1)}%'
                                '  (${scores.where((s) => s >= threshold).length}/${scores.length})',
                                style: const TextStyle(
                                    color: Colors.cyanAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          Slider(
                            value: threshold,
                            min: 0,
                            max: 1,
                            divisions: 100,
                            activeColor: Colors.cyanAccent,
                            inactiveColor:
                                Colors.white.withValues(alpha: 0.2),
                            onChanged: (v) => ref
                                .read(analyticsThresholdProvider.notifier)
                                .set(v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── KPI grid ─────────────────────────────────────────
                    _SectionCard(
                      child: Row(
                        children: [
                          _KpiTile('ทั้งหมด', '${attempts.length}'),
                          _KpiTile('mean',
                              scores.isEmpty
                                  ? '—'
                                  : '${(mean * 100).toStringAsFixed(1)}%'),
                          _KpiTile('median',
                              sorted.isEmpty
                                  ? '—'
                                  : '${(med * 100).toStringAsFixed(1)}%'),
                          _KpiTile('pass',
                              scores.isEmpty
                                  ? '—'
                                  : '${passRate.toStringAsFixed(1)}%'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Pass-rate curve ──────────────────────────────────
                    _ChartCard(
                      repaintKey: _passRateKey,
                      title: 'Pass-rate vs Threshold',
                      shareFilename: 'pass_rate_curve.png',
                      child: PassRateCurveChart(
                          scores: scores, threshold: threshold),
                    ),
                    const SizedBox(height: 12),

                    // ── Histogram ────────────────────────────────────────
                    _ChartCard(
                      repaintKey: _histKey,
                      title: 'Histogram (face_score distribution)',
                      shareFilename: 'histogram.png',
                      child: HistogramChart(
                        scores: scores,
                        threshold: threshold,
                        mean: mean,
                        median: med,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Box plot per test_case ───────────────────────────
                    _ChartCard(
                      repaintKey: _boxKey,
                      title: 'Box plot ต่อเคสทดสอบ',
                      shareFilename: 'box_plot.png',
                      child: BoxPlotPerCaseChart(
                          groups: groups, threshold: threshold),
                    ),
                    const SizedBox(height: 12),

                    // ── Confusion matrix ─────────────────────────────────
                    _ChartCard(
                      repaintKey: _confKey,
                      title: 'Confusion matrix + KPI ต่อเคส',
                      shareFilename: 'confusion_matrix.png',
                      child: ConfusionMatrixCard(
                        attempts: attempts,
                        labels: labels,
                        threshold: threshold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Label editor ─────────────────────────────────────
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('ตั้งค่า Live / Spoof ต่อเคส',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                          const SizedBox(height: 8),
                          const TestCaseLabelEditor(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Shared layout helpers ────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white.withValues(alpha: 0.07),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      );
}

class _ChartCard extends StatelessWidget {
  final GlobalKey repaintKey;
  final String title;
  final String shareFilename;
  final Widget child;

  const _ChartCard({
    required this.repaintKey,
    required this.title,
    required this.shareFilename,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withValues(alpha: 0.07),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share_outlined,
                      color: Colors.white38, size: 18),
                  tooltip: 'แชร์กราฟนี้',
                  onPressed: () =>
                      sharePng(repaintKey, filename: shareFilename, context: context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RepaintBoundary(
              key: repaintKey,
              child: Container(
                  color: const Color(0xFF121212), child: child),
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  const _KpiTile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      );
}

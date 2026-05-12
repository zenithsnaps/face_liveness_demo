import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../application/analytics/face_score_stats.dart' as stats;
import '../../domain/entities/attempt_record.dart';
import '../../domain/failures/liveness_failure.dart';
import '../providers/analytics_provider.dart';
import '../providers/test_cases_provider.dart';
import '../utils/share_png.dart';
import '../widgets/analytics/bell_curve_chart.dart';
import '../widgets/analytics/box_plot_per_case_chart.dart';
import '../widgets/analytics/confusion_matrix_card.dart';
import '../widgets/analytics/far_frr_curve_chart.dart';
import '../widgets/analytics/label_split_histogram_chart.dart';
import '../widgets/analytics/pass_rate_curve_chart.dart';
import '../widgets/analytics/chart_help.dart';
import '../widgets/analytics/test_case_label_editor.dart';
import 'failing_attempts_screen.dart';

final _dtFmt = DateFormat('d MMM yy HH:mm');

class AnalyticsScreen extends ConsumerStatefulWidget {
  /// face_score (0–1) of the attempt that opened this screen, used to draw a
  /// "เคสนี้" marker on the bell curve. Null when opened without a context
  /// attempt (e.g. from a top-level menu).
  final double? currentScore;

  const AnalyticsScreen({super.key, this.currentScore});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  final _fullKey = GlobalKey();
  final _passRateKey = GlobalKey();
  final _histKey = GlobalKey();
  final _labelHistKey = GlobalKey();
  final _farFrrKey = GlobalKey();
  final _boxKey = GlobalKey();
  final _confKey = GlobalKey();

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final filters = ref.read(analyticsFiltersProvider);

    final initialRange = (filters.range == AnalyticsDateRange.custom &&
            filters.customFrom != null &&
            filters.customUntil != null)
        ? DateTimeRange(start: filters.customFrom!, end: filters.customUntil!)
        : DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: initialRange,
      builder: (ctx, child) => Theme(
        data: _darkPickerTheme(),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(filters.customFrom ?? picked.start),
      helpText: 'เวลาเริ่มต้น',
      builder: (ctx, child) => Theme(data: _darkPickerTheme(), child: child!),
    );
    if (!mounted) return;

    final endTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          filters.customUntil ?? picked.end.copyWith(hour: 23, minute: 59)),
      helpText: 'เวลาสิ้นสุด',
      builder: (ctx, child) => Theme(data: _darkPickerTheme(), child: child!),
    );
    if (!mounted) return;

    final from = DateTime(
      picked.start.year, picked.start.month, picked.start.day,
      startTime?.hour ?? 0, startTime?.minute ?? 0,
    );
    final until = DateTime(
      picked.end.year, picked.end.month, picked.end.day,
      endTime?.hour ?? 23, endTime?.minute ?? 59, 59,
    );

    ref.read(analyticsFiltersProvider.notifier).setCustomRange(from, until);
  }

  ThemeData _darkPickerTheme() => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      );

  @override
  Widget build(BuildContext context) {
    final attemptsAsync = ref.watch(analyticsAttemptsProvider);
    final threshold = ref.watch(analyticsThresholdProvider);
    final filters = ref.watch(analyticsFiltersProvider);
    final histYMode = ref.watch(histogramYModeProvider);
    final allCases =
        ref.watch(testCasesListProvider).valueOrNull ?? const <String>[];
    final labels =
        ref.watch(testCaseLabelsProvider).valueOrNull ??
            const <String, TestCaseLabel>{};

    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      child: Scaffold(
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

          // Group by Live/Spoof label for density histogram + FAR/FRR
          TestCaseLabel labelOf(AttemptRecord a) =>
              labels[a.testCase] ?? TestCaseLabel.unlabeled;
          final scoresByLabel = <TestCaseLabel, List<double>>{};
          for (final a in attempts) {
            if (a.faceScore == null) continue;
            scoresByLabel
                .putIfAbsent(labelOf(a), () => [])
                .add(a.faceScore!);
          }
          final liveScores =
              scoresByLabel[TestCaseLabel.live] ?? const <double>[];
          final spoofScores =
              scoresByLabel[TestCaseLabel.spoof] ?? const <double>[];

          // Failure reasons present in data ∪ default excluded set
          final presentReasons = attempts
              .where((a) => a.failureReason != null)
              .map((a) => a.failureReason!)
              .toSet();
          final shownReasons = {
            ...AnalyticsFilters.defaultExcludedFailures,
            ...presentReasons,
          };

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
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: AnalyticsDateRange.values.map((r) {
                              final selected = filters.range == r;
                              return ChoiceChip(
                                label: Text(r.label),
                                selected: selected,
                                onSelected: (_) {
                                  if (r == AnalyticsDateRange.custom) {
                                    _pickCustomRange();
                                  } else {
                                    ref
                                        .read(analyticsFiltersProvider.notifier)
                                        .setRange(r);
                                  }
                                },
                              );
                            }).toList(),
                          ),
                          if (filters.range == AnalyticsDateRange.custom &&
                              filters.customFrom != null &&
                              filters.customUntil != null) ...[
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: _pickCustomRange,
                              child: Text(
                                '${_dtFmt.format(filters.customFrom!)}  –  ${_dtFmt.format(filters.customUntil!)}',
                                style: const TextStyle(
                                    color: Colors.cyanAccent, fontSize: 11),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: DeviceFilter.values.map((d) {
                              final selected = filters.device == d;
                              return ChoiceChip(
                                label: Text(d.label,
                                    style: const TextStyle(fontSize: 11)),
                                selected: selected,
                                onSelected: (_) => ref
                                    .read(analyticsFiltersProvider.notifier)
                                    .setDevice(d),
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
                          // ── Failure-reason filter ────────────────────────
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'ไม่นับเคสที่ check อื่นจับได้',
                                  style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton(
                                style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                onPressed: () => ref
                                    .read(analyticsFiltersProvider.notifier)
                                    .resetExcludedFailures(),
                                child: const Text('reset',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: shownReasons.map((reason) {
                              final excluded =
                                  filters.excludedFailures.contains(reason);
                              final thai = _failureThai(reason);
                              return FilterChip(
                                label: Text(thai,
                                    style: const TextStyle(fontSize: 11)),
                                selected: excluded,
                                selectedColor:
                                    Colors.redAccent.withValues(alpha: 0.25),
                                checkmarkColor: Colors.redAccent,
                                onSelected: (_) => ref
                                    .read(analyticsFiltersProvider.notifier)
                                    .toggleExcludedFailure(reason),
                              );
                            }).toList(),
                          ),
                          if (filters.excludedFailures.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'กรองเคสที่ถูก reject จาก check อื่นออก เพื่อ tune face_score threshold จากเคสที่เหลือ',
                                style: const TextStyle(
                                    color: Colors.white24, fontSize: 10),
                              ),
                            ),
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
                          _KpiTile(
                            'pass',
                            scores.isEmpty
                                ? '—'
                                : '${passRate.toStringAsFixed(1)}%',
                            trailing: scores.any((s) => s < threshold)
                                ? IconButton(
                                    icon: const Icon(Icons.list_alt,
                                        color: Colors.cyanAccent, size: 18),
                                    tooltip: 'ดูเคสที่ไม่ผ่าน',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const FailingAttemptsScreen(),
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Pass-rate curve ──────────────────────────────────
                    _ChartCard(
                      repaintKey: _passRateKey,
                      title: 'Pass-rate vs Threshold',
                      shareFilename: 'pass_rate_curve.png',
                      helpId: ChartId.passRate,
                      child: PassRateCurveChart(
                          scores: scores, threshold: threshold),
                    ),
                    const SizedBox(height: 12),

                    // ── Bell curve (Gaussian fit) ────────────────────────
                    _ChartCard(
                      repaintKey: _histKey,
                      title: 'Bell curve (face_score distribution)',
                      shareFilename: 'bell_curve.png',
                      helpId: ChartId.bellCurve,
                      headerTrailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModeChip(
                            label: 'Count',
                            selected: histYMode == HistogramYMode.count,
                            onTap: () => ref
                                .read(histogramYModeProvider.notifier)
                                .set(HistogramYMode.count),
                          ),
                          const SizedBox(width: 4),
                          _ModeChip(
                            label: 'Density',
                            selected: histYMode == HistogramYMode.density,
                            onTap: () => ref
                                .read(histogramYModeProvider.notifier)
                                .set(HistogramYMode.density),
                          ),
                        ],
                      ),
                      child: BellCurveChart(
                        scores: scores,
                        threshold: threshold,
                        mean: mean,
                        median: med,
                        currentScore: widget.currentScore,
                        yMode: histYMode,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Label-split density histogram ────────────────────
                    _ChartCard(
                      repaintKey: _labelHistKey,
                      title: 'Histogram Live vs Spoof (density)',
                      shareFilename: 'label_split_histogram.png',
                      helpId: ChartId.labelSplit,
                      child: LabelSplitHistogramChart(
                        scoresByLabel: scoresByLabel,
                        threshold: threshold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── FAR / FRR curve ──────────────────────────────────
                    _ChartCard(
                      repaintKey: _farFrrKey,
                      title: 'FAR / FRR curve + EER',
                      shareFilename: 'far_frr_curve.png',
                      helpId: ChartId.farFrr,
                      child: FarFrrCurveChart(
                        liveScores: liveScores,
                        spoofScores: spoofScores,
                        threshold: threshold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Box plot per test_case ───────────────────────────
                    _ChartCard(
                      repaintKey: _boxKey,
                      title: 'Box plot ต่อเคสทดสอบ',
                      shareFilename: 'box_plot.png',
                      helpId: ChartId.boxPlot,
                      child: BoxPlotPerCaseChart(
                          groups: groups, threshold: threshold),
                    ),
                    const SizedBox(height: 12),

                    // ── Confusion matrix ─────────────────────────────────
                    _ChartCard(
                      repaintKey: _confKey,
                      title: 'Confusion matrix + KPI ต่อเคส',
                      shareFilename: 'confusion_matrix.png',
                      helpId: ChartId.confusion,
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
  final Widget? headerTrailing;
  final ChartId? helpId;

  const _ChartCard({
    required this.repaintKey,
    required this.title,
    required this.shareFilename,
    required this.child,
    this.headerTrailing,
    this.helpId,
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
                if (helpId != null)
                  IconButton(
                    icon: const Icon(Icons.info_outline,
                        color: Colors.white38, size: 18),
                    tooltip: 'อธิบายกราฟ',
                    onPressed: () => showChartHelp(context, helpId!),
                  ),
                ?headerTrailing,
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

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ModeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? Colors.cyanAccent.withValues(alpha: 0.2)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? Colors.cyanAccent.withValues(alpha: 0.6)
                  : Colors.white24,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: selected ? Colors.cyanAccent : Colors.white38,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      );
}

/// Maps a raw failure reason name to a short Thai display label.
String _failureThai(String reason) {
  try {
    final failure =
        LivenessFailure.values.firstWhere((f) => f.name == reason);
    return failure.thaiMessage;
  } catch (_) {
    return reason;
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _KpiTile(this.label, this.value, {this.trailing});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  trailing!,
                ],
              ],
            ),
            Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      );
}

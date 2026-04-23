import 'package:flutter/material.dart';

import '../../../application/analytics/face_score_stats.dart' as stats;
import '../../../domain/entities/attempt_record.dart';
import '../../providers/analytics_provider.dart';

/// Confusion matrix and per-case KPI table at the given threshold.
///
/// Rows labeled [TestCaseLabel.live] contribute TP/FN.
/// Rows labeled [TestCaseLabel.spoof] contribute FP/TN.
/// Unlabeled rows are excluded from the matrix.
class ConfusionMatrixCard extends StatelessWidget {
  final List<AttemptRecord> attempts;
  final Map<String, TestCaseLabel> labels;
  final double threshold;

  const ConfusionMatrixCard({
    super.key,
    required this.attempts,
    required this.labels,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    int tp = 0, fn = 0, fp = 0, tn = 0;

    for (final a in attempts) {
      final score = a.faceScore;
      final lbl = labels[a.testCase ?? ''] ?? TestCaseLabel.unlabeled;
      if (lbl == TestCaseLabel.unlabeled || score == null) continue;
      final passesThreshold = score >= threshold;
      if (lbl == TestCaseLabel.live) {
        if (passesThreshold) { tp++; } else { fn++; }
      } else {
        if (passesThreshold) { fp++; } else { tn++; }
      }
    }

    final total = tp + fn + fp + tn;
    if (total == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'ยังไม่มีการ label test_case — กด chip ด้านล่างเพื่อตั้งค่า Live / Spoof',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }

    // ─── Per-case KPI table ──────────────────────────────────────────────────
    final caseGroups = <String, List<double>>{};
    for (final a in attempts) {
      if (a.faceScore == null) continue;
      final key = a.testCase ?? '(ไม่ระบุ)';
      caseGroups.putIfAbsent(key, () => []).add(a.faceScore!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 2×2 matrix
        Row(
          children: [
            const SizedBox(width: 80),
            _MatrixHeader('Predict Pass'),
            _MatrixHeader('Predict Fail'),
          ],
        ),
        Row(
          children: [
            _RowLabel('Actual Live'),
            _MatrixCell(tp, total, color: Colors.greenAccent),
            _MatrixCell(fn, total, color: Colors.redAccent),
          ],
        ),
        Row(
          children: [
            _RowLabel('Actual Spoof'),
            _MatrixCell(fp, total, color: Colors.orangeAccent),
            _MatrixCell(tn, total, color: Colors.greenAccent),
          ],
        ),
        const SizedBox(height: 12),
        if (caseGroups.isNotEmpty) ...[
          const Text('สถิติต่อเคส',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 14,
              headingRowHeight: 28,
              dataRowMinHeight: 26,
              dataRowMaxHeight: 26,
              headingTextStyle: const TextStyle(
                  color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w600),
              dataTextStyle:
                  const TextStyle(color: Colors.white, fontSize: 11),
              columns: const [
                DataColumn(label: Text('เคส')),
                DataColumn(label: Text('n'), numeric: true),
                DataColumn(label: Text('mean'), numeric: true),
                DataColumn(label: Text('median'), numeric: true),
                DataColumn(label: Text('p10'), numeric: true),
                DataColumn(label: Text('p90'), numeric: true),
                DataColumn(label: Text('pass%'), numeric: true),
              ],
              rows: caseGroups.entries.map((e) {
                final sorted = [...e.value]..sort();
                final s = stats.summarize(sorted);
                final passRate =
                    stats.passRateAtThreshold(e.value, threshold) * 100;
                String fmt(double v) =>
                    '${(v * 100).toStringAsFixed(1)}%';
                return DataRow(cells: [
                  DataCell(Text(
                    e.key.length > 16
                        ? '${e.key.substring(0, 14)}…'
                        : e.key,
                  )),
                  DataCell(Text('${e.value.length}')),
                  DataCell(Text(fmt(s.mean))),
                  DataCell(Text(fmt(s.median))),
                  DataCell(Text(fmt(stats.quantile(sorted, 0.10)))),
                  DataCell(Text(fmt(stats.quantile(sorted, 0.90)))),
                  DataCell(Text('${passRate.toStringAsFixed(1)}%')),
                ]);
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _MatrixHeader extends StatelessWidget {
  final String text;
  const _MatrixHeader(this.text);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          height: 28,
          alignment: Alignment.center,
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ),
      );
}

class _RowLabel extends StatelessWidget {
  final String text;
  const _RowLabel(this.text);
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 80,
        child: Text(text,
            style: const TextStyle(color: Colors.white54, fontSize: 10)),
      );
}

class _MatrixCell extends StatelessWidget {
  final int count;
  final int total;
  final Color color;
  const _MatrixCell(this.count, this.total, {required this.color});
  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total * 100).toStringAsFixed(1) : '—';
    return Expanded(
      child: Container(
        height: 56,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$count',
                style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            Text('$pct%',
                style:
                    TextStyle(color: color.withValues(alpha: 0.75), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

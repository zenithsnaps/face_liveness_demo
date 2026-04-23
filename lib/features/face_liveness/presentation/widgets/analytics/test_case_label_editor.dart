import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/analytics_provider.dart';
import '../../providers/test_cases_provider.dart';

/// Chip row that cycles each test_case through live → spoof → unlabeled.
/// Drives the confusion matrix.
class TestCaseLabelEditor extends ConsumerWidget {
  const TestCaseLabelEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cases = ref.watch(testCasesListProvider).valueOrNull ?? const [];
    final labelsAsync = ref.watch(testCaseLabelsProvider);
    final labels =
        labelsAsync.valueOrNull ?? const <String, TestCaseLabel>{};

    if (cases.isEmpty) {
      return const Text(
        'ยังไม่มีเคสทดสอบ — เพิ่มได้จากหน้าหลัก',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: cases.map((c) {
        final lbl = labels[c] ?? TestCaseLabel.unlabeled;
        final color = switch (lbl) {
          TestCaseLabel.live => Colors.greenAccent,
          TestCaseLabel.spoof => Colors.orangeAccent,
          TestCaseLabel.unlabeled => Colors.white38,
        };
        return GestureDetector(
          onTap: () =>
              ref.read(testCaseLabelsProvider.notifier).cycle(c),
          child: Chip(
            backgroundColor: color.withValues(alpha: 0.15),
            side: BorderSide(color: color.withValues(alpha: 0.6)),
            label: Text(
              '$c  [${lbl.display}]',
              style: TextStyle(color: color, fontSize: 11),
            ),
          ),
        );
      }).toList(),
    );
  }
}

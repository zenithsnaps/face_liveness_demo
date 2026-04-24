import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_strings.dart';
import '../providers/post_capture_checks_provider.dart';
import '../providers/post_capture_thresholds_provider.dart';
import '../providers/test_cases_provider.dart';
import '../providers/tester_provider.dart';
import 'face_liveness_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _testerController = TextEditingController();
  bool _seeded = false;

  @override
  void dispose() {
    _testerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testerAsync = ref.watch(testerNameProvider);
    testerAsync.whenData((name) {
      if (!_seeded) {
        _seeded = true;
        _testerController.text = name;
      }
    });

    final thresholds = ref.watch(postCaptureThresholdsProvider);
    final ctrl = ref.read(postCaptureThresholdsProvider.notifier);
    final checks = ref.watch(postCaptureChecksProvider);
    final checksCtrl = ref.read(postCaptureChecksProvider.notifier);
    final testCases = ref.watch(testCasesListProvider);
    final selectedCase = ref.watch(selectedTestCaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ชื่อผู้ทดสอบ',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _testerController,
                      decoration: const InputDecoration(
                        hintText: 'พิมพ์ชื่อผู้ทดสอบ',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.done,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'เคสทดสอบ',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: testCases.when(
                            data: (cases) => DropdownButton<String?>(
                              isExpanded: true,
                              value: cases.contains(selectedCase) ? selectedCase : null,
                              hint: const Text('เลือกเคสทดสอบ (optional)'),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(
                                    '(ไม่ระบุ)',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ),
                                ...cases.map(
                                  (c) => DropdownMenuItem<String?>(
                                    value: c,
                                    child: Text(c, overflow: TextOverflow.ellipsis),
                                  ),
                                ),
                              ],
                              onChanged: (v) => ref
                                  .read(selectedTestCaseProvider.notifier)
                                  .select(v),
                            ),
                            loading: () => const LinearProgressIndicator(),
                            error: (_, _) =>
                                const Text('โหลดเคสไม่สำเร็จ', style: TextStyle(color: Colors.red)),
                          ),
                        ),
                        IconButton(
                          tooltip: 'เพิ่มเคสใหม่',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _showAddCaseDialog(context, ref),
                        ),
                        if (selectedCase != null)
                          IconButton(
                            tooltip: 'ลบเคสนี้',
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () =>
                                _confirmDelete(context, ref, selectedCase),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'เลือกการตรวจสอบหลังถ่าย',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Face detection', style: TextStyle(fontSize: 13)),
                      value: checks.faceEnabled,
                      onChanged: checksCtrl.setFaceEnabled,
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Hand landmarker', style: TextStyle(fontSize: 13)),
                      value: checks.handEnabled,
                      onChanged: checksCtrl.setHandEnabled,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          ref.invalidate(postCaptureChecksProvider);
                          ref.invalidate(postCaptureThresholdsProvider);
                        },
                        child: const Text('Reset to defaults'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Post-capture thresholds',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _ThresholdSlider(
                      label: 'Face score min',
                      value: thresholds.faceScore,
                      min: 0.50,
                      max: 1.00,
                      divisions: 50,
                      onChanged: ctrl.setFaceScore,
                    ),
                    _ThresholdSlider(
                      label: 'Hand confidence',
                      value: thresholds.handConfidence,
                      min: 0.10,
                      max: 1.00,
                      divisions: 90,
                      onChanged: ctrl.setHandConfidence,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () async {
                await ref
                    .read(testerNameProvider.notifier)
                    .set(_testerController.text);
                if (!context.mounted) return;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FaceLivenessScreen(),
                  ),
                );
              },
              child: const Text(
                AppStrings.startVerification,
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAddCaseDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('เพิ่มเคสทดสอบ'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'เช่น ทดสอบมีมือบัง'),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('เพิ่ม'),
        ),
      ],
    ),
  );
  if (name != null && name.trim().isNotEmpty) {
    await ref.read(testCasesListProvider.notifier).addCase(name);
  }
}

Future<void> _confirmDelete(
    BuildContext context, WidgetRef ref, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ลบเคสทดสอบ?'),
      content: Text('ต้องการลบเคส "$name" หรือไม่'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('ลบ'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await ref.read(testCasesListProvider.notifier).removeCase(name);
  }
}

class _ThresholdSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _ThresholdSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pct = '${(value * 100).toStringAsFixed(0)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 13)),
            Text(pct, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

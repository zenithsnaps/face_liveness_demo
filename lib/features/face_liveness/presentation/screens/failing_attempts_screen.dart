import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/attempt_record.dart';
import '../../domain/failures/liveness_failure.dart';
import '../providers/analytics_provider.dart';
import 'image_viewer_screen.dart';

final _dtFmt = DateFormat('d MMM yy HH:mm');

class FailingAttemptsScreen extends ConsumerWidget {
  const FailingAttemptsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attemptsAsync = ref.watch(analyticsAttemptsProvider);
    final threshold = ref.watch(analyticsThresholdProvider);

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
          title: Text(
            'เคสที่ไม่ผ่าน (score < ${(threshold * 100).toStringAsFixed(0)}%)',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: attemptsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'โหลดไม่สำเร็จ: $e',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          data: (attempts) {
            final failing = attempts
                .where((a) => a.faceScore != null && a.faceScore! < threshold)
                .toList()
              ..sort((a, b) => a.faceScore!.compareTo(b.faceScore!));
            if (failing.isEmpty) {
              return const Center(
                child: Text(
                  'ไม่มีเคสที่ไม่ผ่าน',
                  style: TextStyle(color: Colors.white54),
                ),
              );
            }
            return ListView.separated(
              itemCount: failing.length,
              separatorBuilder: (context, i) =>
                  const Divider(height: 1, color: Colors.white12),
              itemBuilder: (_, i) => _FailingRow(attempt: failing[i]),
            );
          },
        ),
      ),
    );
  }
}

class _FailingRow extends StatelessWidget {
  final AttemptRecord attempt;

  const _FailingRow({required this.attempt});

  @override
  Widget build(BuildContext context) {
    final hasImage = attempt.summaryUrl != null;
    final scoreText =
        'face_score: ${(attempt.faceScore! * 100).toStringAsFixed(1)}%'
        '  •  ${attempt.testCase ?? '(ไม่ระบุ)'}';
    final reasonText =
        '${_failureThai(attempt.failureReason)}  •  ${_dtFmt.format(attempt.completedAt)}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: GestureDetector(
        onTap: hasImage ? () => _openImage(context) : null,
        child: SizedBox(
          width: 56,
          height: 56,
          child: hasImage
              ? Hero(
                  tag: attempt.id,
                  child: Image.network(
                    attempt.summaryUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _ImagePlaceholder(),
                  ),
                )
              : const _ImagePlaceholder(),
        ),
      ),
      title: Text(
        attempt.testerName ?? '(ไม่ระบุ)',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(scoreText,
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 11)),
          Text(reasonText,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
      onTap: hasImage ? () => _openImage(context) : null,
    );
  }

  void _openImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          url: attempt.summaryUrl!,
          heroTag: attempt.id,
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white.withValues(alpha: 0.07),
        child: const Icon(
          Icons.image_not_supported,
          color: Colors.white24,
          size: 28,
        ),
      );
}

String _failureThai(String? reason) {
  if (reason == null) return '—';
  try {
    return LivenessFailure.values.firstWhere((f) => f.name == reason).thaiMessage;
  } catch (_) {
    return reason;
  }
}

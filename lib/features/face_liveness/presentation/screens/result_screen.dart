import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_strings.dart';
import '../../domain/entities/eye_occlusion_evidence.dart';
import '../../domain/repositories/liveness_result_repository.dart';
import '../coordinators/batch_capture_coordinator.dart';
import '../providers/liveness_providers.dart';
import '../providers/post_capture_checks_provider.dart';
import 'analytics_screen.dart';

class ResultScreen extends ConsumerStatefulWidget {
  final CaptureSession session;
  final String? testCase;
  final String? tester;
  final String? cameraResolution;

  const ResultScreen({
    super.key,
    required this.session,
    required this.testCase,
    this.tester,
    this.cameraResolution,
  });

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  String? _remoteGroupId;
  bool _persisting = false;
  bool _persistFailed = false;

  @override
  void initState() {
    super.initState();
    // Pre-cache the face-max photo so it renders sharp immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await precacheImage(
          FileImage(File(widget.session.faceMaxFrame.jpegPath)),
          context,
        );
      } catch (_) {}
    });
  }

  Future<void> _uploadAll() async {
    final repo = ref.read(livenessResultRepositoryProvider);
    if (repo == null) return;
    setState(() {
      _persisting = true;
      _persistFailed = false;
    });

    final draft = ref.read(attemptDraftProvider);
    if (draft == null) {
      setState(() => _persisting = false);
      return;
    }

    DeviceContext device;
    try {
      device = await ref.read(deviceContextProvider.future);
    } catch (_) {
      setState(() {
        _persisting = false;
        _persistFailed = true;
      });
      return;
    }
    if (widget.cameraResolution != null) {
      device = device.copyWith(cameraResolution: widget.cameraResolution);
    }

    final completedAt = DateTime.now().toUtc();
    final checks = ref.read(postCaptureChecksProvider);
    String? groupId;
    try {
      groupId = await repo.persistSession(
        session: widget.session,
        draftStartedAt: draft.startedAt,
        completedAt: completedAt,
        device: device,
        checks: checks,
        testCase: widget.testCase,
        testerName: widget.tester,
      );
    } catch (e, st) {
      debugPrint('[ResultScreen] persistSession threw (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      setState(() {
        _persisting = false;
        _persistFailed = true;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _persisting = false;
      if (groupId != null) {
        _remoteGroupId = groupId;
      } else {
        _persistFailed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(livenessResultRepositoryProvider);
    final supabaseEnabled = repo != null;
    final frames = widget.session.frames;
    final faceMax = widget.session.faceMaxFrame;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.verificationSuccess),
        bottom: widget.testCase != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(28),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.label_outline, size: 13),
                      const SizedBox(width: 4),
                      Text(
                        widget.testCase!,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (supabaseEnabled) ...[
                _buildSyncBanner(),
                if (_remoteGroupId == null) ...[
                  const SizedBox(height: 8),
                  _buildUploadButton(),
                ],
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('ดูสรุปภาพรวม'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AnalyticsScreen(
                        currentScore: faceMax.score.faceScore,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
              ],
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                child: const Text(AppStrings.done),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          _MainPhotoCard(frame: faceMax),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.photo_library_outlined, size: 18),
              const SizedBox(width: 6),
              Text(
                'รายละเอียดทุกเฟรม (${frames.length} ภาพ)',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final f in frames) ...[
            _FrameRow(frame: f, isFaceMax: identical(f, faceMax)),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadButton() {
    if (_remoteGroupId != null) return const SizedBox.shrink();
    if (_persisting) {
      return FilledButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        label: const Text(AppStrings.cloudSaving),
      );
    }
    if (_persistFailed) {
      return OutlinedButton.icon(
        onPressed: _uploadAll,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text(AppStrings.cloudRetry),
      );
    }
    return FilledButton.icon(
      onPressed: _uploadAll,
      icon: const Icon(Icons.cloud_upload),
      label: Text('${AppStrings.cloudUpload} (${widget.session.frames.length})'),
    );
  }

  Widget _buildSyncBanner() {
    if (_persisting) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            AppStrings.cloudSaving,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }
    if (_persistFailed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          border: Border.all(color: Colors.amber.shade200),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppStrings.cloudSyncFailed,
                style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
              ),
            ),
          ],
        ),
      );
    }
    if (_remoteGroupId != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border.all(color: Colors.green.shade200),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_done, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${AppStrings.cloudSaved} · ${_remoteGroupId!.substring(0, 8)}',
                style: TextStyle(fontSize: 12, color: Colors.green.shade800),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _MainPhotoCard extends StatelessWidget {
  final CapturedFrame frame;
  const _MainPhotoCard({required this.frame});

  @override
  Widget build(BuildContext context) {
    final scorePct =
        '${(frame.score.faceScore * 100).toStringAsFixed(1)}%';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Image.file(
                File(frame.jpegPath),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.verified, color: Colors.green.shade700, size: 26),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ภาพหลัก (face score สูงสุด)',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                    Text(
                      scorePct,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameRow extends StatelessWidget {
  final CapturedFrame frame;
  final bool isFaceMax;
  const _FrameRow({required this.frame, required this.isFaceMax});

  @override
  Widget build(BuildContext context) {
    final score = frame.score;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isFaceMax ? Colors.green.shade50 : Colors.white,
        border: Border.all(
          color: isFaceMax ? Colors.green.shade300 : Colors.black12,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 84,
              height: 112,
              child: Image.file(
                File(frame.jpegPath),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '#${frame.sequence}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    if (isFaceMax) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.star, size: 12, color: Colors.green.shade700),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                _MetricLine(
                  label: 'Face confidence',
                  value: '${(score.faceScore * 100).toStringAsFixed(1)}%',
                ),
                _MetricLine(
                  label: 'Hands detected',
                  value: '${score.handCount}',
                  emphasize: score.handCount > 0,
                ),
                _MetricLine(
                  label: 'Eye combined',
                  value: score.eyeEvidence != null
                      ? score.eyeEvidence!.combinedScore.toStringAsFixed(2)
                      : '—',
                  emphasize: score.eyeEvidence?.occluded ?? false,
                ),
                if (score.eyeEvidence != null) ...[
                  const SizedBox(height: 4),
                  _EyeEvidenceMini(evidence: score.eyeEvidence!),
                ],
                _MetricLine(
                  label: 'Sunglasses (TFLite)',
                  value: score.glassesEvidence != null
                      ? 'P=${score.glassesEvidence!.sunglassesProba.toStringAsFixed(2)}'
                      : '—',
                  emphasize: score.glassesEvidence?.isWearingSunglasses ?? false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const _MetricLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: emphasize ? Colors.red.shade700 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _EyeEvidenceMini extends StatelessWidget {
  final EyeOcclusionEvidence evidence;
  const _EyeEvidenceMini({required this.evidence});

  @override
  Widget build(BuildContext context) {
    String f1(double v) => v.toStringAsFixed(1);
    String f2(double v) => v.toStringAsFixed(2);
    final rows = <(String, String)>[
      ('Lum L/R', '${f2(evidence.leftLumRatio)} / ${f2(evidence.rightLumRatio)}'),
      ('Std L/R', '${f1(evidence.leftStdDev)} / ${f1(evidence.rightStdDev)}'),
      ('Sat L/R',
          '${f1(evidence.leftSaturation)} / ${f1(evidence.rightSaturation)}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.$1,
                    style: const TextStyle(fontSize: 10, color: Colors.black45),
                  ),
                ),
                Text(
                  r.$2,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

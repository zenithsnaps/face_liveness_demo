import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_strings.dart';
import '../../application/usecases/post_capture_checks.dart';
import '../../application/usecases/post_capture_thresholds.dart';
import '../../application/usecases/validate_capture.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/liveness_result_repository.dart';
import '../providers/liveness_providers.dart';
import '../utils/widget_snapshot.dart';
import 'analytics_screen.dart';

class ResultScreen extends ConsumerStatefulWidget {
  final String photoPath;
  final CaptureValidationResult validation;
  final PostCaptureThresholds thresholds;
  final PostCaptureChecks checks;
  final String? testCase;

  const ResultScreen({
    super.key,
    required this.photoPath,
    required this.validation,
    required this.thresholds,
    required this.checks,
    required this.testCase,
  });

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  final _summaryKey = GlobalKey();
  String? _remoteAttemptId;
  bool _persisting = false;
  bool _persistFailed = false;

  @override
  void initState() {
    super.initState();
    // Pre-cache the photo so it renders correctly when the RepaintBoundary
    // snapshot is captured at upload time.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await precacheImage(FileImage(File(widget.photoPath)), context);
      } catch (_) {}
    });
  }

  Future<void> _captureAndPersist() async {
    final repo = ref.read(livenessResultRepositoryProvider);
    if (repo == null) return;

    setState(() {
      _persisting = true;
      _persistFailed = false;
    });

    final png = await captureBoundaryPng(_summaryKey);

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

    final completedAt = DateTime.now().toUtc();
    final id = await repo.persistAttempt(
      draft: draft,
      completedAt: completedAt,
      passed: widget.validation.passed,
      failure: widget.validation.failure,
      failureMessage: widget.validation.failure?.thaiMessage,
      faceScore: widget.validation.faceScore,
      thresholds: widget.thresholds,
      checks: widget.checks,
      captureValidation: widget.validation,
      summaryPng: png,
      device: device,
      testCase: widget.testCase,
    );

    if (!mounted) return;
    setState(() {
      _persisting = false;
      if (id != null) {
        _remoteAttemptId = id;
      } else {
        _persistFailed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(livenessResultRepositoryProvider);
    final supabaseEnabled = repo != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.validation.passed
              ? AppStrings.verificationSuccess
              : AppStrings.captureFailedTitle,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // RepaintBoundary captures this section as the summary snapshot
            Expanded(
              child: RepaintBoundary(
                key: _summaryKey,
                child: Container(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(widget.photoPath),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ValidationCard(validation: widget.validation),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Cloud sync section (outside RepaintBoundary — not part of snapshot)
            if (supabaseEnabled) ...[
              _buildSyncBanner(),
              const SizedBox(height: 8),
              _buildUploadButton(),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.analytics_outlined),
                label: const Text('ดูสรุปภาพรวม'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AnalyticsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],

            const Text(
              AppStrings.photoPathLabel,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(widget.photoPath),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((r) => r.isFirst),
              child: Text(
                  widget.validation.passed ? AppStrings.done : AppStrings.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadButton() {
    // Hide once uploaded successfully.
    if (_remoteAttemptId != null) return const SizedBox.shrink();

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
        onPressed: _captureAndPersist,
        icon: const Icon(Icons.cloud_upload_outlined),
        label: const Text(AppStrings.cloudRetry),
      );
    }

    return FilledButton.icon(
      onPressed: _captureAndPersist,
      icon: const Icon(Icons.cloud_upload),
      label: const Text(AppStrings.cloudUpload),
    );
  }

  Widget _buildSyncBanner() {
    if (_persisting) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          const Text(
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
    if (_remoteAttemptId != null) {
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
                '${AppStrings.cloudSaved} · ${_remoteAttemptId!.substring(0, 8)}',
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

class _ValidationCard extends StatelessWidget {
  final CaptureValidationResult validation;
  const _ValidationCard({required this.validation});

  @override
  Widget build(BuildContext context) {
    final passed = validation.passed;
    final color = passed ? Colors.green : Colors.red;
    final icon = passed ? Icons.verified : Icons.cancel_outlined;
    final scoreText = validation.faceScore != null
        ? '${(validation.faceScore! * 100).toStringAsFixed(1)}%'
        : 'N/A';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.captureFailedSubtitle,
            style: TextStyle(fontSize: 12, color: color.shade700),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: color.shade700, size: 28),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.faceScoreLabel,
                    style: TextStyle(fontSize: 12, color: color.shade700),
                  ),
                  Text(
                    scoreText,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: color.shade800,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (validation.failure != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 18, color: color.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      validation.failure!.thaiMessage,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: color.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/app_strings.dart';
import '../../application/usecases/validate_capture.dart';
import '../../domain/failures/liveness_failure.dart';

class ResultScreen extends StatelessWidget {
  final String photoPath;
  final CaptureValidationResult validation;

  const ResultScreen({
    super.key,
    required this.photoPath,
    required this.validation,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          validation.passed ? AppStrings.verificationSuccess : AppStrings.captureFailedTitle,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
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
                  child: Image.file(File(photoPath), fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ValidationCard(validation: validation),
            const SizedBox(height: 12),
            const Text(
              AppStrings.photoPathLabel,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SelectableText(photoPath),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: Text(validation.passed ? AppStrings.done : AppStrings.retry),
            ),
          ],
        ),
      ),
    );
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

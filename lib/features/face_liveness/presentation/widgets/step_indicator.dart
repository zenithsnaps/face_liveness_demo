import 'package:flutter/material.dart';

import '../../../../core/app_strings.dart';
import '../../domain/entities/liveness_gate.dart';

class StepIndicator extends StatelessWidget {
  final LivenessGate? currentGate;

  const StepIndicator({super.key, required this.currentGate});

  @override
  Widget build(BuildContext context) {
    final steps = [
      (_StepPhase.frame, AppStrings.stepFrame),
      (_StepPhase.liveness, AppStrings.stepLiveness),
    ];
    final activePhase = _phaseFor(currentGate);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final (phase, label) in steps)
          _StepDot(
            label: label,
            active: phase == activePhase,
            done: _isDone(phase, activePhase),
          ),
      ],
    );
  }

  _StepPhase? _phaseFor(LivenessGate? gate) {
    if (gate == null) return null;
    return switch (gate) {
      LivenessGate.faceQuality => _StepPhase.frame,
      LivenessGate.livenessSmile => _StepPhase.liveness,
      LivenessGate.livenessBlink => _StepPhase.liveness,
    };
  }

  bool _isDone(_StepPhase phase, _StepPhase? current) {
    if (current == null) return false;
    return phase.index < current.index;
  }
}

enum _StepPhase { frame, liveness }

class _StepDot extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;
  const _StepDot({
    required this.label,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (done) {
      color = const Color(0xFF34C759);
    } else if (active) {
      color = Colors.white;
    } else {
      color = Colors.white24;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }
}

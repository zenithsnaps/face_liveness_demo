import 'package:flutter/material.dart';

import '../widgets/face_oval_overlay.dart';

class InstructionBanner extends StatelessWidget {
  final String text;
  final OvalStatus status;

  const InstructionBanner({
    super.key,
    required this.text,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    switch (status) {
      case OvalStatus.failure:
        bg = const Color(0xFFFF3B30);
        fg = Colors.white;
      case OvalStatus.success:
        bg = const Color(0xFF34C759);
        fg = Colors.white;
      case OvalStatus.working:
      case OvalStatus.neutral:
        bg = Colors.white;
        fg = Colors.black87;
    }
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            switch (status) {
              OvalStatus.failure => Icons.error_outline,
              OvalStatus.success => Icons.check_circle_outline,
              OvalStatus.neutral => Icons.info_outline,
              OvalStatus.working => Icons.info_outline,
            },
            color: fg,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

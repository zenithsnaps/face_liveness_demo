import 'package:flutter/material.dart';

enum ChartId { passRate, bellCurve, labelSplit, farFrr, boxPlot, confusion }

class ChartHelp {
  final String title;
  final String howToRead;
  final String useFor;
  final String? caveat;

  const ChartHelp({
    required this.title,
    required this.howToRead,
    required this.useFor,
    this.caveat,
  });
}

const Map<ChartId, ChartHelp> chartHelp = {
  ChartId.passRate: ChartHelp(
    title: 'Pass-rate vs Threshold',
    howToRead:
        'แกน X = threshold (0–100%), แกน Y = % ของเคสที่จะผ่าน\n'
        'เส้นขาวลาดลงจากซ้ายไปขวา — threshold สูงขึ้น ผ่านน้อยลง\n'
        'เส้นฟ้า (จุดๆ) = threshold ที่เลือกอยู่ตอนนี้',
    useFor:
        'ตอบคำถาม "ถ้าตั้ง threshold ที่ X% จะมีกี่ % ของเคสที่ผ่าน?"\n'
        'ใช้ประมาณผลกระทบต่อ UX ก่อนเปลี่ยน threshold จริง',
  ),
  ChartId.bellCurve: ChartHelp(
    title: 'Bell Curve (การกระจายของ face_score)',
    howToRead:
        'ทรงระฆังคว่ำ: ยอด = score ที่เกิดบ่อยที่สุด, ฐานกว้าง = กระจายออก\n'
        'μ เหลือง = mean,  Med ส้ม = median,  T ฟ้า = threshold\n'
        'เส้นชมพู = เคสนี้ (มีเฉพาะเมื่อเปิดจากหน้า Result)\n'
        'pinch zoom เพื่อขยาย, double-tap เพื่อ reset',
    useFor:
        'ดูว่าเคสนี้อยู่จุดไหนเทียบกับทุกเคส\n'
        'ถ้าเส้นชมพูอยู่ขวา threshold = ผ่าน, อยู่ซ้าย = ไม่ผ่าน',
    caveat:
        'ระฆังนี้คือ Gaussian fit (โมเดลทฤษฎี) ไม่ใช่ bar chart ข้อมูลจริง\n'
        'ดูข้อมูลดิบได้ที่กราฟ Histogram Live vs Spoof',
  ),
  ChartId.labelSplit: ChartHelp(
    title: 'Histogram Live vs Spoof (density)',
    howToRead:
        'bar เขียว = Live (คนจริง),  bar แดง = Spoof (ปลอม)\n'
        'แกน X = score 0–100%,  แกน Y = % ของเคสในแต่ละกลุ่มที่ score อยู่ช่วงนั้น\n'
        'เส้นฟ้า (จุดๆ) = threshold',
    useFor:
        'ดูว่าระบบแยก Live vs Spoof ได้ชัดแค่ไหน\n'
        'bar เขียวกองขวา + bar แดงกองซ้าย = ระบบแยกได้ดี\n'
        'สองสีทับกันมาก = บริเวณนั้นเสี่ยงผิดพลาดสูง',
    caveat: 'ต้อง label test_case ก่อน — ดูที่ "ตั้งค่า Live / Spoof ต่อเคส" ล่างสุด',
  ),
  ChartId.farFrr: ChartHelp(
    title: 'FAR / FRR curve + EER',
    howToRead:
        'FRR แดง = % คนจริงที่โดน reject,  FAR น้ำเงิน = % ปลอมที่เล็ดลอดผ่าน\n'
        'แกน X = threshold,  แกน Y = % ผิดพลาด\n'
        'จุดเหลือง (EER) = threshold ที่ FAR = FRR พอดี (จุดสมดุล)',
    useFor:
        'threshold ต่ำ → FAR สูง (ปลอมผ่านง่าย)\n'
        'threshold สูง → FRR สูง (คนจริงโดน reject)\n'
        'เริ่มจาก EER แล้ว bias ตามความต้องการ: ปลอดภัย = เพิ่ม threshold, UX = ลด',
    caveat: 'ต้อง label test_case ก่อน — ดูที่ "ตั้งค่า Live / Spoof ต่อเคส" ล่างสุด',
  ),
  ChartId.boxPlot: ChartHelp(
    title: 'Box Plot ต่อเคสทดสอบ',
    howToRead:
        'แต่ละกล่อง = 1 test_case\n'
        'ขอบบน = Q3 (75%), ขอบล่าง = Q1 (25%), เส้นส้มกลาง = median\n'
        'จุดเหลือง = mean,  เส้น = min/max,  เส้นฟ้าแนวนอน = threshold',
    useFor:
        'เปรียบเทียบ test_case ว่าแต่ละกลุ่มทำคะแนนต่างกันยังไง\n'
        'กล่องเตี้ย = score consistent,  กล่องสูง = score กระจาย\n'
        'threshold ผ่ากลางกล่อง = เคสนี้ borderline ต้องระวัง',
  ),
  ChartId.confusion: ChartHelp(
    title: 'Confusion Matrix + KPI ต่อเคส',
    howToRead:
        'ตาราง 2×2: แถว = ความจริง (Live/Spoof), คอลัมน์ = ระบบทาย (ผ่าน/ไม่ผ่าน)\n'
        'TP = คนจริงผ่าน ✅,  FN = คนจริงโดน reject ❌\n'
        'FP = ปลอมผ่าน ❌,  TN = ปลอมถูก block ✅',
    useFor:
        'นับชัดๆ ว่าระบบผิดกี่เคสและผิดแบบไหน ที่ threshold นี้\n'
        'FN สูง = UX แย่ (คนจริงโดน block),  FP สูง = ปลอดภัยน้อย (ปลอมเล็ดลอด)',
    caveat: 'ต้อง label test_case ก่อน — ดูที่ "ตั้งค่า Live / Spoof ต่อเคส" ล่างสุด',
  ),
};

Future<void> showChartHelp(BuildContext context, ChartId id) {
  final h = chartHelp[id]!;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            h.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _HelpSection(label: 'ดูยังไง', text: h.howToRead),
          _HelpSection(label: 'เอาไปทำอะไรต่อ', text: h.useFor),
          if (h.caveat != null)
            _HelpSection(label: 'ระวัง', text: h.caveat!, warning: true),
          const SizedBox(height: 4),
        ],
      ),
    ),
  );
}

class _HelpSection extends StatelessWidget {
  final String label;
  final String text;
  final bool warning;

  const _HelpSection({
    required this.label,
    required this.text,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = warning ? Colors.amberAccent : Colors.cyanAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

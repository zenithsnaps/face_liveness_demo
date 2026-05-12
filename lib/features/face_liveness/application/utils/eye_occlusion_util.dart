import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/entities/eye_occlusion_evidence.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/value_objects/rect2d.dart';
import 'eye_occlusion_thresholds.dart';

/// Detects dark glasses by comparing eye vs cheek region statistics.
///
/// Ported 1:1 from the production Kotlin app
/// (`FaceDetectionUtils.isWearingSunglasses`):
///   1. Derives 4 ROI rectangles from faceBox geometry alone — no ML Kit
///      contours/landmarks required.
///   2. Pools pixels across left+right eye into one stats calculation; same
///      for cheeks.
///   3. Uses HSV-style saturation `(max - min) / max * 255`.
///   4. Weighted-bucket scoring with three signals (lumRatio, stdDev, sat).
///   5. Blocks when total score ≥ blockScore (default 0.30 = suspicious).
///
/// [frame] must be RGBA8888, already rotated upright.
/// [faceBox] is the detected face bounding box in upright-frame coordinates.
/// [mirrored] flips the bbox horizontally for the rare case where the bitmap
/// is mirrored relative to where the bbox was detected (front camera bitmaps
/// that were already flipped before being fed to a non-mirrored detector).
class EyeOcclusionUtil {
  const EyeOcclusionUtil._();

  static EyeOcclusionEvidence detect({
    required FrameData frame,
    required Rect2D faceBox,
    EyeOcclusionThresholds thresholds = EyeOcclusionThresholds.defaults,
    bool mirrored = false,
  }) {
    final bytes = frame.bytes is Uint8List
        ? frame.bytes as Uint8List
        : Uint8List.fromList(frame.bytes);
    final imgW = frame.width;
    final imgH = frame.height;
    if (imgW <= 0 || imgH <= 0) return _empty();
    final imageBounds = Rect2D.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble());

    var rect = faceBox;
    if (mirrored) {
      rect = Rect2D.fromLTRB(
        imgW - rect.right,
        rect.top,
        imgW - rect.left,
        rect.bottom,
      );
    }
    final clipped = _intersect(rect, imageBounds);
    if (clipped == null || clipped.width < 40 || clipped.height < 40) {
      return _empty();
    }
    rect = clipped;

    final fw = rect.width;
    final fh = rect.height;
    final leftEye = Rect2D.fromLTRB(
      rect.left + fw * 0.16,
      rect.top + fh * 0.30,
      rect.left + fw * 0.44,
      rect.top + fh * 0.46,
    );
    final rightEye = Rect2D.fromLTRB(
      rect.left + fw * 0.56,
      rect.top + fh * 0.30,
      rect.left + fw * 0.84,
      rect.top + fh * 0.46,
    );
    final leftCheek = Rect2D.fromLTRB(
      rect.left + fw * 0.18,
      rect.top + fh * 0.58,
      rect.left + fw * 0.43,
      rect.top + fh * 0.76,
    );
    final rightCheek = Rect2D.fromLTRB(
      rect.left + fw * 0.57,
      rect.top + fh * 0.58,
      rect.left + fw * 0.82,
      rect.top + fh * 0.76,
    );

    final eyeStats = _statsOver(bytes, imgW, imgH, [leftEye, rightEye]);
    final cheekStats = _statsOver(bytes, imgW, imgH, [leftCheek, rightCheek]);
    if (eyeStats == null || cheekStats == null || cheekStats.meanY <= 1.0) {
      return _empty();
    }

    final luminanceRatio = eyeStats.meanY / cheekStats.meanY;
    final score = _bucketScore(
      luminanceRatio: luminanceRatio,
      eyeStdDev: eyeStats.stdY,
      eyeSaturation: eyeStats.meanSat,
      t: thresholds,
    );

    // Per-eye breakdown is informational (chip + supabase). Decision uses
    // the pooled `score`. We re-run the pooling formula on each eye in
    // isolation so the diagnostic values line up with what the decision sees.
    final leftEyeStats = _statsOver(bytes, imgW, imgH, [leftEye]);
    final rightEyeStats = _statsOver(bytes, imgW, imgH, [rightEye]);
    final leftLumRatio = leftEyeStats != null && cheekStats.meanY > 0
        ? leftEyeStats.meanY / cheekStats.meanY
        : 0.0;
    final rightLumRatio = rightEyeStats != null && cheekStats.meanY > 0
        ? rightEyeStats.meanY / cheekStats.meanY
        : 0.0;
    final leftScore = _bucketScore(
      luminanceRatio: leftLumRatio,
      eyeStdDev: leftEyeStats?.stdY ?? 0.0,
      eyeSaturation: leftEyeStats?.meanSat ?? 0.0,
      t: thresholds,
    );
    final rightScore = _bucketScore(
      luminanceRatio: rightLumRatio,
      eyeStdDev: rightEyeStats?.stdY ?? 0.0,
      eyeSaturation: rightEyeStats?.meanSat ?? 0.0,
      t: thresholds,
    );

    return EyeOcclusionEvidence(
      referenceLuminance: cheekStats.meanY,
      leftLumRatio: leftLumRatio,
      rightLumRatio: rightLumRatio,
      leftStdDev: leftEyeStats?.stdY ?? 0.0,
      rightStdDev: rightEyeStats?.stdY ?? 0.0,
      leftSaturation: leftEyeStats?.meanSat ?? 0.0,
      rightSaturation: rightEyeStats?.meanSat ?? 0.0,
      leftScore: leftScore,
      rightScore: rightScore,
      combinedScore: score,
      occluded: score >= thresholds.blockScore,
    );
  }

  /// Production's weighted bucket scoring.
  ///
  ///   Lum ratio  < block (0.35) → +0.45,   < pass (0.55) → +0.30,  else 0
  ///   StdDev     < block (8)    → +0.30,   < pass (15)   → +0.18,  else 0
  ///   Saturation < block (12)   → +0.25,   < pass (20)   → +0.15,  else 0
  ///
  /// Max possible score = 1.00. Block at ≥ 0.30 (one suspicious-lum signal
  /// alone is enough; one opaque signal almost reaches block on its own).
  static double _bucketScore({
    required double luminanceRatio,
    required double eyeStdDev,
    required double eyeSaturation,
    required EyeOcclusionThresholds t,
  }) {
    double s = 0;
    if (luminanceRatio < t.lumRatioBlock) {
      s += 0.45;
    } else if (luminanceRatio < t.lumRatioPass) {
      s += 0.30;
    }
    if (eyeStdDev < t.stdDevBlock) {
      s += 0.30;
    } else if (eyeStdDev < t.stdDevPass) {
      s += 0.18;
    }
    if (eyeSaturation < t.saturationBlock) {
      s += 0.25;
    } else if (eyeSaturation < t.saturationPass) {
      s += 0.15;
    }
    return s;
  }

  static EyeOcclusionEvidence _empty() => const EyeOcclusionEvidence(
        referenceLuminance: 0,
        leftLumRatio: 0,
        rightLumRatio: 0,
        leftStdDev: 0,
        rightStdDev: 0,
        leftSaturation: 0,
        rightSaturation: 0,
        leftScore: 0,
        rightScore: 0,
        combinedScore: 0,
        occluded: false,
      );

  static Rect2D? _intersect(Rect2D a, Rect2D b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    if (right <= left || bottom <= top) return null;
    return Rect2D.fromLTRB(left, top, right, bottom);
  }

  static _RegionStats? _statsOver(
    Uint8List bytes,
    int imgW,
    int imgH,
    List<Rect2D> rects,
  ) {
    double count = 0;
    double sumY = 0;
    double sumY2 = 0;
    double sumSat = 0;

    for (final raw in rects) {
      final left = math.max(0, raw.left.floor());
      final top = math.max(0, raw.top.floor());
      final right = math.min(imgW, raw.right.ceil());
      final bottom = math.min(imgH, raw.bottom.ceil());
      if (right - left < 4 || bottom - top < 4) continue;

      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final i = 4 * (y * imgW + x);
          final r = bytes[i].toDouble();
          final g = bytes[i + 1].toDouble();
          final b = bytes[i + 2].toDouble();
          final yLum = 0.299 * r + 0.587 * g + 0.114 * b;
          final maxRgb = math.max(r, math.max(g, b));
          final minRgb = math.min(r, math.min(g, b));
          final sat = maxRgb <= 0 ? 0.0 : ((maxRgb - minRgb) / maxRgb) * 255.0;
          count++;
          sumY += yLum;
          sumY2 += yLum * yLum;
          sumSat += sat;
        }
      }
    }
    if (count <= 0) return null;
    final meanY = sumY / count;
    final variance = math.max((sumY2 / count) - meanY * meanY, 0.0);
    return _RegionStats(
      meanY: meanY,
      stdY: math.sqrt(variance),
      meanSat: sumSat / count,
    );
  }
}

class _RegionStats {
  final double meanY;
  final double stdY;
  final double meanSat;
  const _RegionStats({
    required this.meanY,
    required this.stdY,
    required this.meanSat,
  });
}

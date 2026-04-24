import 'dart:math' as math;
import 'dart:typed_data';

import '../../../../core/app_constants.dart';
import '../../domain/entities/eye_occlusion_evidence.dart';
import '../../domain/entities/eye_regions.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/value_objects/point2d.dart';
import '../../domain/value_objects/rect2d.dart';

/// Post-capture check: detect sunglasses or other eye-covering objects via
/// pixel-level analysis of the eye contour regions.
///
/// Three signals, each scored 0→1 with linear interpolation in the
/// suspicious range:
///   1. Lum Ratio (eyeLum / cheekLum): pass > 0.55 → score 0, block < 0.35 → score 1
///   2. StdDev (luminance σ inside eye):  pass > 15 → score 0, block < 8  → score 1
///   3. Saturation (mean max−min, 0–255): pass > 20 → score 0, block < 12 → score 1
///
/// Combined Score = mean(lumScore, stdDevScore, satScore) per eye.
/// Final score = max(leftScore, rightScore). Blocked when ≥ 0.5.
class CheckNoEyeOcclusion {
  const CheckNoEyeOcclusion();

  EyeOcclusionEvidence call({
    required FrameData frame,
    required EyeRegions regions,
  }) {
    final bytes = frame.bytes is Uint8List
        ? frame.bytes as Uint8List
        : Uint8List.fromList(frame.bytes);
    final w = frame.width;
    final h = frame.height;

    final refLum = _referenceLuminance(bytes, w, h, regions);
    final leftStats = _eyeStats(bytes, w, h, regions.leftEye);
    final rightStats = _eyeStats(bytes, w, h, regions.rightEye);

    final leftRatio = refLum > 0 ? leftStats.lumMean / refLum : 1.0;
    final rightRatio = refLum > 0 ? rightStats.lumMean / refLum : 1.0;

    final leftScore = _combinedScore(leftRatio, leftStats.stdDev, leftStats.saturation);
    final rightScore = _combinedScore(rightRatio, rightStats.stdDev, rightStats.saturation);
    final combined = math.max(leftScore, rightScore);

    return EyeOcclusionEvidence(
      referenceLuminance: refLum,
      leftLumRatio: leftRatio,
      rightLumRatio: rightRatio,
      leftStdDev: leftStats.stdDev,
      rightStdDev: rightStats.stdDev,
      leftSaturation: leftStats.saturation,
      rightSaturation: rightStats.saturation,
      leftScore: leftScore,
      rightScore: rightScore,
      combinedScore: combined,
      occluded: combined >= AppConstants.eyeOcclusionBlockScore,
    );
  }

  double _combinedScore(double lumRatio, double stdDev, double saturation) {
    final s1 = _signalScore(lumRatio, AppConstants.eyeLumRatioPass, AppConstants.eyeLumRatioBlock);
    final s2 = _signalScore(stdDev, AppConstants.eyeStdDevPass, AppConstants.eyeStdDevBlock);
    final s3 = _signalScore(saturation, AppConstants.eyeSaturationPass, AppConstants.eyeSaturationBlock);
    return (s1 + s2 + s3) / 3;
  }

  /// Linear score 0 (pass) → 1 (block). Works for all three signals where
  /// higher value = better (lower = more occluded).
  double _signalScore(double value, double passThreshold, double blockThreshold) {
    if (value >= passThreshold) return 0.0;
    if (value <= blockThreshold) return 1.0;
    return (passThreshold - value) / (passThreshold - blockThreshold);
  }

  ({double lumMean, double stdDev, double saturation}) _eyeStats(
    Uint8List bytes,
    int w,
    int h,
    List<Point2D> contour,
  ) {
    if (contour.isEmpty) return (lumMean: 128.0, stdDev: 20.0, saturation: 30.0);
    final bbox = _bbox(contour);
    // Inset by 15% on each side to stay inside the lens, away from skin edges.
    final region = _inset(bbox, 0.15);
    return _sampleRegion(bytes, w, h, region);
  }

  double _referenceLuminance(
    Uint8List bytes,
    int w,
    int h,
    EyeRegions regions,
  ) {
    final patchSize = regions.faceBox.width * 0.08;
    final lumValues = <double>[];

    for (final cheek in [regions.leftCheek, regions.rightCheek]) {
      if (cheek == null) continue;
      final rect = Rect2D.fromLTWH(
        cheek.x - patchSize / 2,
        cheek.y - patchSize / 2,
        patchSize,
        patchSize,
      );
      lumValues.add(_sampleRegion(bytes, w, h, rect).lumMean);
    }

    if (lumValues.isEmpty) {
      // Fallback: strip just below each eye bbox.
      final fallbackH = regions.faceBox.height * 0.10;
      for (final contour in [regions.leftEye, regions.rightEye]) {
        if (contour.isEmpty) continue;
        final eyeBbox = _bbox(contour);
        final rect = Rect2D.fromLTWH(
          eyeBbox.left, eyeBbox.bottom + 4, eyeBbox.width, fallbackH,
        );
        lumValues.add(_sampleRegion(bytes, w, h, rect).lumMean);
      }
    }

    if (lumValues.isEmpty) return 180.0;
    return lumValues.reduce((a, b) => a + b) / lumValues.length;
  }

  Rect2D _bbox(List<Point2D> pts) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    return Rect2D.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect2D _inset(Rect2D r, double factor) {
    final dx = r.width * factor;
    final dy = r.height * factor;
    return Rect2D.fromLTWH(
      r.left + dx, r.top + dy, r.width - 2 * dx, r.height - 2 * dy,
    );
  }

  ({double lumMean, double stdDev, double saturation}) _sampleRegion(
    Uint8List bytes,
    int imgW,
    int imgH,
    Rect2D rect,
  ) {
    final left = rect.left.round().clamp(0, imgW - 1);
    final top = rect.top.round().clamp(0, imgH - 1);
    final right = rect.right.round().clamp(0, imgW);
    final bottom = rect.bottom.round().clamp(0, imgH);
    if (left >= right || top >= bottom) {
      return (lumMean: 128.0, stdDev: 20.0, saturation: 30.0);
    }

    double sumY = 0;
    double sumY2 = 0;
    double sumSat = 0;
    int count = 0;
    for (var y = top; y < bottom; y += 2) {
      for (var x = left; x < right; x += 2) {
        final i = 4 * (y * imgW + x);
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        final mx = math.max(r, math.max(g, b));
        final mn = math.min(r, math.min(g, b));
        sumY += lum;
        sumY2 += lum * lum;
        sumSat += (mx - mn).toDouble();
        count++;
      }
    }
    if (count == 0) return (lumMean: 128.0, stdDev: 20.0, saturation: 30.0);

    final mean = sumY / count;
    final variance = (sumY2 / count) - (mean * mean);
    return (
      lumMean: mean,
      stdDev: math.sqrt(math.max(0.0, variance)),
      saturation: sumSat / count,
    );
  }
}

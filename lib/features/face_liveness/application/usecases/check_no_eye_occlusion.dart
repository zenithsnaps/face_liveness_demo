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
/// Three signals are combined (all must hold for both eyes):
///   1. Low luminance  — dark lens absorbs light (< [eyeMaxLuminance])
///   2. Low saturation — dark/grey lens has flat color (< [eyeMaxSaturation])
///   3. High contrast vs cheek — covered eye looks much darker than skin
///      (referenceLuminance - eyeLuminance ≥ [eyeMinContrastVsReference])
class CheckNoEyeOcclusion {
  const CheckNoEyeOcclusion();

  EyeOcclusionEvidence call({
    required FrameData frame,
    required EyeRegions regions,
    double eyeMaxLuminance = AppConstants.eyeMaxLuminanceDefault,
    double eyeMaxSaturation = AppConstants.eyeMaxSaturationDefault,
    double eyeMinContrastVsReference = AppConstants.eyeMinContrastVsReferenceDefault,
  }) {
    final bytes = frame.bytes is Uint8List
        ? frame.bytes as Uint8List
        : Uint8List.fromList(frame.bytes);
    final w = frame.width;
    final h = frame.height;

    final leftStats = _eyeStats(bytes, w, h, regions.leftEye);
    final rightStats = _eyeStats(bytes, w, h, regions.rightEye);
    final refStats = _referenceStats(bytes, w, h, regions);

    final leftContrast = refStats.luminance - leftStats.luminance;
    final rightContrast = refStats.luminance - rightStats.luminance;

    final occluded = leftStats.luminance <= eyeMaxLuminance &&
        rightStats.luminance <= eyeMaxLuminance &&
        leftStats.saturation <= eyeMaxSaturation &&
        rightStats.saturation <= eyeMaxSaturation &&
        leftContrast >= eyeMinContrastVsReference &&
        rightContrast >= eyeMinContrastVsReference;

    return EyeOcclusionEvidence(
      leftEyeLuminance: leftStats.luminance,
      rightEyeLuminance: rightStats.luminance,
      leftEyeSaturation: leftStats.saturation,
      rightEyeSaturation: rightStats.saturation,
      referenceLuminance: refStats.luminance,
      referenceSaturation: refStats.saturation,
      leftContrast: leftContrast,
      rightContrast: rightContrast,
      occluded: occluded,
    );
  }

  ({double luminance, double saturation}) _eyeStats(
    Uint8List bytes,
    int w,
    int h,
    List<Point2D> contour,
  ) {
    if (contour.isEmpty) return (luminance: 128.0, saturation: 0.5);
    final bbox = _bbox(contour);
    // Inset by 15% on each side to sample inside the lens, away from skin edges.
    final region = _inset(bbox, 0.15);
    return _sampleRegion(bytes, w, h, region);
  }

  ({double luminance, double saturation}) _referenceStats(
    Uint8List bytes,
    int w,
    int h,
    EyeRegions regions,
  ) {
    final patchSize = regions.faceBox.width * 0.08;
    final patches = <({double luminance, double saturation})>[];

    for (final cheek in [regions.leftCheek, regions.rightCheek]) {
      if (cheek == null) continue;
      final rect = Rect2D.fromLTWH(
        cheek.x - patchSize / 2,
        cheek.y - patchSize / 2,
        patchSize,
        patchSize,
      );
      patches.add(_sampleRegion(bytes, w, h, rect));
    }

    if (patches.isEmpty) {
      // Fallback: sample a strip just below each eye bbox.
      final fallbackH = regions.faceBox.height * 0.10;
      for (final contour in [regions.leftEye, regions.rightEye]) {
        if (contour.isEmpty) continue;
        final eyeBbox = _bbox(contour);
        final rect = Rect2D.fromLTWH(
          eyeBbox.left,
          eyeBbox.bottom + 4,
          eyeBbox.width,
          fallbackH,
        );
        patches.add(_sampleRegion(bytes, w, h, rect));
      }
    }

    if (patches.isEmpty) return (luminance: 180.0, saturation: 0.3);

    final lum =
        patches.map((p) => p.luminance).reduce((a, b) => a + b) / patches.length;
    final sat =
        patches.map((p) => p.saturation).reduce((a, b) => a + b) / patches.length;
    return (luminance: lum, saturation: sat);
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
      r.left + dx,
      r.top + dy,
      r.width - 2 * dx,
      r.height - 2 * dy,
    );
  }

  ({double luminance, double saturation}) _sampleRegion(
    Uint8List bytes,
    int imgW,
    int imgH,
    Rect2D rect,
  ) {
    final left = rect.left.round().clamp(0, imgW - 1);
    final top = rect.top.round().clamp(0, imgH - 1);
    final right = rect.right.round().clamp(0, imgW);
    final bottom = rect.bottom.round().clamp(0, imgH);
    if (left >= right || top >= bottom) return (luminance: 128.0, saturation: 0.5);

    double sumY = 0;
    double sumS = 0;
    int count = 0;
    for (var y = top; y < bottom; y += 2) {
      for (var x = left; x < right; x += 2) {
        final i = 4 * (y * imgW + x);
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        sumY += 0.299 * r + 0.587 * g + 0.114 * b;
        final mx = math.max(r, math.max(g, b));
        final mn = math.min(r, math.min(g, b));
        sumS += mx == 0 ? 0.0 : (mx - mn) / mx;
        count++;
      }
    }
    if (count == 0) return (luminance: 128.0, saturation: 0.5);
    return (luminance: sumY / count, saturation: sumS / count);
  }
}

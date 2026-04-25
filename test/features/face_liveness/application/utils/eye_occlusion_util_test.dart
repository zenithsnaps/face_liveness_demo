import 'dart:typed_data';

import 'package:face_liveness_demo/core/app_constants.dart';
import 'package:face_liveness_demo/features/face_liveness/application/utils/eye_occlusion_thresholds.dart';
import 'package:face_liveness_demo/features/face_liveness/application/utils/eye_occlusion_util.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/eye_regions.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_metadata.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/point2d.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/rect2d.dart';
import 'package:flutter_test/flutter_test.dart';

// ─── Synthetic frame helpers ────────────────────────────────────────────────

const _imgW = 200;
const _imgH = 300;

// Eye bounding rectangles (image-pixel coordinates).
const _leftEyeL = 30.0, _leftEyeT = 80.0, _leftEyeR = 90.0, _leftEyeB = 120.0;
const _rightEyeL = 110.0, _rightEyeT = 80.0, _rightEyeR = 170.0, _rightEyeB = 120.0;

// After 15% inset (60×40 → dx=9, dy=6): left eye → (39,86,81,114)
// Sampled columns at stride-2 starting at x=39: 39,41,43,... → 39%4=3 (dark), 41%4=1 (bright), alternating.

/// Base frame filled with skin tone (R=200, G=175, B=150).
Uint8List _makeBaseFrame() {
  final bytes = Uint8List(_imgW * _imgH * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = 200;
    bytes[i + 1] = 175;
    bytes[i + 2] = 150;
    bytes[i + 3] = 255;
  }
  return bytes;
}

/// Overwrite [x0,x1) × [y0,y1) with a solid RGBA colour.
void _fillSolid(Uint8List bytes, int x0, int y0, int x1, int y1, int r, int g, int b) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = 4 * (y * _imgW + x);
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = 255;
    }
  }
}

/// Overwrite [x0,x1) × [y0,y1) with a period-4 checker:
///   x%4 ∈ {0,1} → bright colorful (R=220, G=220, B=100)
///   x%4 ∈ {2,3} → dark (R=20, G=20, B=20)
///
/// At stride-2 sampling (x = x0, x0+2, x0+4 …) the parity of x%4 flips each
/// step, so the sampler sees alternating bright/dark pixels — giving high
/// stdDev, high mean lum relative to cheek, and high saturation.
void _fillChecker(Uint8List bytes, int x0, int y0, int x1, int y1) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = 4 * (y * _imgW + x);
      if (x % 4 < 2) {
        bytes[i] = 220;
        bytes[i + 1] = 220;
        bytes[i + 2] = 100;
      } else {
        bytes[i] = 20;
        bytes[i + 1] = 20;
        bytes[i + 2] = 20;
      }
      bytes[i + 3] = 255;
    }
  }
}

FrameData _wrapBytes(Uint8List bytes) => FrameData(
      bytes: bytes,
      metadata: const FrameMetadata(
        width: _imgW,
        height: _imgH,
        rotationDegrees: 0,
        format: FramePixelFormat.rgba8888,
        timestampMicros: 0,
      ),
    );

List<Point2D> _leftEyeContour() => const [
      Point2D(_leftEyeL, _leftEyeT),
      Point2D(_leftEyeR, _leftEyeT),
      Point2D(_leftEyeR, _leftEyeB),
      Point2D(_leftEyeL, _leftEyeB),
    ];

List<Point2D> _rightEyeContour() => const [
      Point2D(_rightEyeL, _rightEyeT),
      Point2D(_rightEyeR, _rightEyeT),
      Point2D(_rightEyeR, _rightEyeB),
      Point2D(_rightEyeL, _rightEyeB),
    ];

/// Build EyeRegions. Cheeks default to skin-tone areas in the base frame.
EyeRegions _makeRegions({
  List<Point2D>? leftEye,
  List<Point2D>? rightEye,
  bool includeChecks = true,
}) =>
    EyeRegions(
      leftEye: leftEye ?? _leftEyeContour(),
      rightEye: rightEye ?? _rightEyeContour(),
      faceBox: const Rect2D.fromLTWH(10, 20, 180, 260),
      leftCheek: includeChecks ? const Point2D(60, 200) : null,
      rightCheek: includeChecks ? const Point2D(140, 200) : null,
    );

// ─── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('EyeOcclusionUtil.detect', () {
    late Uint8List frame;

    setUp(() => frame = _makeBaseFrame());

    // ── Happy path ──────────────────────────────────────────────────────────

    test('both eyes clear (checker pattern) → not occluded, low scores', () {
      _fillChecker(frame, 30, 80, 90, 120);
      _fillChecker(frame, 110, 80, 170, 120);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(),
      );

      expect(r.occluded, isFalse);
      expect(r.leftScore, lessThan(0.1));
      expect(r.rightScore, lessThan(0.1));
      expect(r.combinedScore, lessThan(0.1));
    });

    // ── Full block ───────────────────────────────────────────────────────────

    test('both eyes blocked (dark solid) → occluded, score ≈ 1.0', () {
      _fillSolid(frame, 30, 80, 90, 120, 10, 10, 10);
      _fillSolid(frame, 110, 80, 170, 120, 10, 10, 10);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(),
      );

      expect(r.occluded, isTrue);
      expect(r.combinedScore, closeTo(1.0, 0.01));
    });

    // ── Worst-eye wins ───────────────────────────────────────────────────────

    test('left eye clear, right eye blocked → combinedScore == rightScore', () {
      _fillChecker(frame, 30, 80, 90, 120);
      _fillSolid(frame, 110, 80, 170, 120, 10, 10, 10);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(),
      );

      expect(r.occluded, isTrue);
      expect(r.rightScore, closeTo(1.0, 0.01));
      expect(r.leftScore, lessThan(0.1));
      expect(r.combinedScore, closeTo(r.rightScore, 0.001));
    });

    // ── Fallback paths ───────────────────────────────────────────────────────

    test('both contours empty → fallback values, not occluded', () {
      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(leftEye: [], rightEye: []),
      );

      expect(r.occluded, isFalse);
      expect(r.leftScore, closeTo(0.0, 0.001));
      expect(r.rightScore, closeTo(0.0, 0.001));
      expect(r.combinedScore, closeTo(0.0, 0.001));
    });

    test('only left contour empty → leftScore = 0, right unaffected', () {
      _fillChecker(frame, 110, 80, 170, 120);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(leftEye: []),
      );

      expect(r.leftScore, closeTo(0.0, 0.001));
      expect(r.occluded, isFalse);
    });

    test('no cheek landmarks → strip-below-eye fallback, clear eyes still pass', () {
      _fillChecker(frame, 30, 80, 90, 120);
      _fillChecker(frame, 110, 80, 170, 120);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(includeChecks: false),
      );

      expect(r.occluded, isFalse);
      expect(r.referenceLuminance, greaterThan(0));
    });

    // ── Threshold override ───────────────────────────────────────────────────

    test('blockScore=1.1 → fully-blocked eyes (score=1.0) are not occluded', () {
      _fillSolid(frame, 30, 80, 90, 120, 10, 10, 10);
      _fillSolid(frame, 110, 80, 170, 120, 10, 10, 10);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(),
        thresholds: const EyeOcclusionThresholds(blockScore: 1.1),
      );

      expect(r.combinedScore, closeTo(1.0, 0.01));
      expect(r.occluded, isFalse);
    });

    test('blockScore boundary: combined ≥ blockScore → occluded (≥ not >)', () {
      _fillSolid(frame, 30, 80, 90, 120, 10, 10, 10);
      _fillSolid(frame, 110, 80, 170, 120, 10, 10, 10);

      final atBoundary = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(),
        thresholds: const EyeOcclusionThresholds(blockScore: 1.0),
      );
      expect(atBoundary.occluded, isTrue);

      final aboveBoundary = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        regions: _makeRegions(),
        thresholds: const EyeOcclusionThresholds(blockScore: 1.1),
      );
      expect(aboveBoundary.occluded, isFalse);
    });

    // ── Default thresholds match AppConstants ────────────────────────────────

    test('default thresholds mirror AppConstants values', () {
      const t = EyeOcclusionThresholds();
      expect(t.lumRatioPass, AppConstants.eyeLumRatioPass);
      expect(t.lumRatioBlock, AppConstants.eyeLumRatioBlock);
      expect(t.stdDevPass, AppConstants.eyeStdDevPass);
      expect(t.stdDevBlock, AppConstants.eyeStdDevBlock);
      expect(t.saturationPass, AppConstants.eyeSaturationPass);
      expect(t.saturationBlock, AppConstants.eyeSaturationBlock);
      expect(t.blockScore, AppConstants.eyeOcclusionBlockScore);
    });
  });
}

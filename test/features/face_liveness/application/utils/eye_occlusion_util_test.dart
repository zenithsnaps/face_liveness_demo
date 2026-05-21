import 'dart:typed_data';

import 'package:face_liveness_demo/core/app_constants.dart';
import 'package:face_liveness_demo/features/face_liveness/application/utils/eye_occlusion_thresholds.dart';
import 'package:face_liveness_demo/features/face_liveness/application/utils/eye_occlusion_util.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_metadata.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/rect2d.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic 200×300 RGBA frame with a 180×260 face bbox at (10, 20).
// Derived ROIs (production geometry):
//   leftEye:    x ∈ [38, 90],  y ∈ [98, 140]
//   rightEye:   x ∈ [110, 162], y ∈ [98, 140]
//   leftCheek:  x ∈ [42, 88],  y ∈ [170, 218]
//   rightCheek: x ∈ [112, 158], y ∈ [170, 218]

const _imgW = 200;
const _imgH = 300;
const _faceBox = Rect2D.fromLTWH(10, 20, 180, 260);

/// Base frame filled with skin tone (R=200, G=175, B=150 — warm beige).
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

void _fillSolid(
    Uint8List bytes, int x0, int y0, int x1, int y1, int r, int g, int b) {
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

/// Period-4 colourful checker — bright/dark stripes that give high stdDev,
/// high HSV-saturation, and mean luminance close to skin.
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

void main() {
  group('EyeOcclusionUtil.detect (production-ported)', () {
    late Uint8List frame;

    setUp(() => frame = _makeBaseFrame());

    test('clear eyes (skin tone everywhere) → not occluded, low score', () {
      // Base frame is solid skin tone → eye region looks like cheek region:
      // lumRatio ≈ 1.0 (pass), but stdDev ≈ 0 (block) and saturation also low.
      // We instead simulate "real" eye region with checker (high std + sat).
      _fillChecker(frame, 38, 98, 90, 140);
      _fillChecker(frame, 110, 98, 162, 140);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        faceBox: _faceBox,
      );

      expect(r.occluded, isFalse);
      expect(r.combinedScore, lessThan(0.30));
    });

    test('dark solid eye region → opaque on lum+sat → score = 0.70', () {
      _fillSolid(frame, 38, 98, 90, 140, 10, 10, 10);
      _fillSolid(frame, 110, 98, 162, 140, 10, 10, 10);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        faceBox: _faceBox,
      );

      // lumRatio (~10/~180) far below 0.35 → +0.45
      // saturation = 0 (max==min) → +0.25
      // stdDev bucket disabled (thresholds = 0) → +0.00
      // → total = 0.70 (was 1.00 before disabling std), occluded
      expect(r.occluded, isTrue);
      expect(r.combinedScore, closeTo(0.70, 0.01));
    });

    test('moderately dark + flat lens → blocked at suspicious threshold', () {
      // Grey lens: meanY ~75 → lumRatio ~0.42 (block <0.35? no, in (0.35, 0.55) → suspicious +0.30)
      _fillSolid(frame, 38, 98, 90, 140, 75, 75, 75);
      _fillSolid(frame, 110, 98, 162, 140, 75, 75, 75);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        faceBox: _faceBox,
      );

      // suspicious-lum (0.30) + opaque-sat (0.25) = 0.55 (was 0.85 with std)
      expect(r.occluded, isTrue);
      expect(r.combinedScore, greaterThanOrEqualTo(0.30));
    });

    test('face too small → empty result', () {
      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        faceBox: const Rect2D.fromLTWH(50, 50, 30, 30),
      );

      expect(r.occluded, isFalse);
      expect(r.combinedScore, 0.0);
      expect(r.referenceLuminance, 0.0);
    });

    test('face entirely outside image bounds → empty result', () {
      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        faceBox: const Rect2D.fromLTWH(500, 500, 100, 100),
      );

      expect(r.combinedScore, 0.0);
    });

    test('mirror flag flips the bbox horizontally', () {
      // Put a dark patch where the MIRRORED eye region would land.
      // Original faceBox (10, 20, 180, 260) → leftEye [38, 90]
      // After mirror (imgW=200): faceBox flipped → faceRight=190, faceLeft=10 (no change since centred near middle)
      // Actually: mirrored faceBox = (imgW-right, top, imgW-left, bottom) = (200-190, 20, 200-10, 280)
      //                            = (10, 20, 190, 280) — same as before! Centred face.
      // Use an off-centre faceBox to actually see the flip:
      const off = Rect2D.fromLTWH(0, 20, 100, 260);
      // Original leftEye region: x ∈ [0+100*0.16, 0+100*0.44] = [16, 44], y ∈ [98, 140]
      // After mirror (imgW=200): bbox → (200-100, 20, 200-0, 280) = (100, 20, 200, 280)
      // Mirrored leftEye: x ∈ [100+100*0.16, 100+100*0.44] = [116, 144]

      _fillSolid(frame, 116, 98, 144, 140, 10, 10, 10);
      // Mirrored rightEye region: x ∈ [100+100*0.56, 100+100*0.84] = [156, 184]
      _fillSolid(frame, 156, 98, 184, 140, 10, 10, 10);

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        faceBox: off,
        mirrored: true,
      );

      expect(r.occluded, isTrue);
    });

    test('blockScore override raises the bar', () {
      _fillSolid(frame, 38, 98, 90, 140, 10, 10, 10);
      _fillSolid(frame, 110, 98, 162, 140, 10, 10, 10);

      // Default 0.30 → occluded. Override 0.80 → score (0.70) < 0.80 → not occluded.
      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        faceBox: _faceBox,
        thresholds: const EyeOcclusionThresholds(blockScore: 0.80),
      );

      expect(r.combinedScore, closeTo(0.70, 0.01));
      expect(r.occluded, isFalse);
    });

    test('default thresholds mirror AppConstants values', () {
      const t = EyeOcclusionThresholds();
      expect(t.lumRatioPass, AppConstants.eyeLumRatioPass);
      expect(t.lumRatioBlock, AppConstants.eyeLumRatioBlock);
      expect(t.stdDevPass, AppConstants.eyeStdDevPass);
      expect(t.stdDevBlock, AppConstants.eyeStdDevBlock);
      expect(t.saturationPass, AppConstants.eyeSaturationPass);
      expect(t.saturationBlock, AppConstants.eyeSaturationBlock);
      expect(t.blockScore, AppConstants.eyeOcclusionBlockScore);
      expect(t.blockScore, 0.30); // production threshold
    });

    test('per-eye evidence is populated (informational)', () {
      _fillSolid(frame, 38, 98, 90, 140, 10, 10, 10); // left dark
      _fillChecker(frame, 110, 98, 162, 140);           // right clear

      final r = EyeOcclusionUtil.detect(
        frame: _wrapBytes(frame),
        faceBox: _faceBox,
      );

      expect(r.leftScore, greaterThan(r.rightScore));
      expect(r.leftStdDev, lessThan(r.rightStdDev));
    });
  });
}

import 'dart:typed_data';

import 'package:face_liveness_demo/core/app_constants.dart';
import 'package:face_liveness_demo/core/result.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_metadata.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/glasses_evidence.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/rect2d.dart';
import 'package:face_liveness_demo/features/face_liveness/infrastructure/mediapipe/mediapipe_glasses_classifier_analyzer.dart';
import 'package:face_liveness_demo/features/face_liveness/infrastructure/platform_channels/mediapipe_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the args the analyzer passes down and returns a canned probability,
/// so we can assert the ROI math without touching the platform channel.
class _FakeMediaPipeChannel extends MediaPipeChannel {
  double proba;
  bool throwOnClassify;

  int classifyCalls = 0;
  FrameData? lastFrame;
  Map<String, double>? lastRoi;

  _FakeMediaPipeChannel({this.proba = 0, this.throwOnClassify = false});

  @override
  Future<void> initialize() async {}

  @override
  Future<double> classifyGlasses(
    FrameData frame, {
    Map<String, double>? roi,
  }) async {
    classifyCalls++;
    lastFrame = frame;
    lastRoi = roi;
    if (throwOnClassify) throw StateError('boom');
    return proba;
  }
}

FrameData _frame({int width = 100, int height = 100}) => FrameData(
      bytes: Uint8List(0),
      metadata: FrameMetadata(
        width: width,
        height: height,
        rotationDegrees: 0,
        format: FramePixelFormat.rgba8888,
        timestampMicros: 0,
      ),
    );

GlassesEvidence _ok(Result<GlassesEvidence, Object> r) =>
    (r as Ok<GlassesEvidence, Object>).value;

void main() {
  group('MediaPipeGlassesClassifierAnalyzer ROI', () {
    test('null faceBox → no ROI (classify whole frame)', () async {
      final ch = _FakeMediaPipeChannel(proba: 0.42);
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch);

      final r = await analyzer.analyze(_frame());

      expect(ch.classifyCalls, 1);
      expect(ch.lastRoi, isNull);
      expect(_ok(r).sunglassesProba, 0.42);
    });

    test('interior faceBox is expanded by cropMargin and normalized', () async {
      final ch = _FakeMediaPipeChannel(proba: 0.9);
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch); // margin 0.6

      // 100×100 frame, face LTWH(40,40,20,20).
      // expanded(0.6): dx=dy=12 → LTRB(28,28,72,72) → all inside frame.
      await analyzer.analyze(
        _frame(),
        faceBox: const Rect2D.fromLTWH(40, 40, 20, 20),
      );

      final roi = ch.lastRoi!;
      expect(roi['left'], closeTo(0.28, 1e-9));
      expect(roi['top'], closeTo(0.28, 1e-9));
      expect(roi['width'], closeTo(0.44, 1e-9));
      expect(roi['height'], closeTo(0.44, 1e-9));
    });

    test('faceBox at the edge is clamped to the frame', () async {
      final ch = _FakeMediaPipeChannel();
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch);

      // face LTWH(0,0,20,20): expanded left/top go negative → clamp to 0,
      // right/bottom = 32. Normalized: (0,0,0.32,0.32).
      await analyzer.analyze(
        _frame(),
        faceBox: const Rect2D.fromLTWH(0, 0, 20, 20),
      );

      final roi = ch.lastRoi!;
      expect(roi['left'], 0.0);
      expect(roi['top'], 0.0);
      expect(roi['width'], closeTo(0.32, 1e-9));
      expect(roi['height'], closeTo(0.32, 1e-9));
    });

    test('collapsed crop (<8px after clamp) → no ROI', () async {
      final ch = _FakeMediaPipeChannel();
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch);

      // Tiny box in the corner: expanded by 0.6 of 1px stays ~2.2px wide → <8.
      await analyzer.analyze(
        _frame(),
        faceBox: const Rect2D.fromLTWH(98, 98, 1, 1),
      );

      expect(ch.classifyCalls, 1);
      expect(ch.lastRoi, isNull); // falls back to whole frame
    });

    test('respects a custom cropMargin', () async {
      final ch = _FakeMediaPipeChannel();
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch, cropMargin: 0.0);

      // margin 0 → ROI == the raw face box, just normalized.
      await analyzer.analyze(
        _frame(),
        faceBox: const Rect2D.fromLTWH(40, 40, 20, 20),
      );

      final roi = ch.lastRoi!;
      expect(roi['left'], closeTo(0.40, 1e-9));
      expect(roi['top'], closeTo(0.40, 1e-9));
      expect(roi['width'], closeTo(0.20, 1e-9));
      expect(roi['height'], closeTo(0.20, 1e-9));
    });
  });

  group('MediaPipeGlassesClassifierAnalyzer evidence', () {
    test('threshold defaults to AppConstants.glassesBlockThreshold', () async {
      final ch = _FakeMediaPipeChannel(proba: 0.8);
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch);

      final ev = _ok(await analyzer.analyze(_frame()));

      expect(ev.threshold, AppConstants.glassesBlockThreshold);
      expect(ev.isWearingSunglasses, isTrue); // 0.8 >= 0.7
    });

    test('proba below threshold → not wearing sunglasses', () async {
      final ch = _FakeMediaPipeChannel(proba: 0.5);
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch);

      final ev = _ok(await analyzer.analyze(_frame()));

      expect(ev.isWearingSunglasses, isFalse); // 0.5 < 0.7
    });

    test('custom threshold is honoured', () async {
      final ch = _FakeMediaPipeChannel(proba: 0.55);
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch, threshold: 0.5);

      final ev = _ok(await analyzer.analyze(_frame()));

      expect(ev.threshold, 0.5);
      expect(ev.isWearingSunglasses, isTrue);
    });
  });

  group('MediaPipeGlassesClassifierAnalyzer failure modes', () {
    test('channel throwing → Err', () async {
      final ch = _FakeMediaPipeChannel(throwOnClassify: true);
      final analyzer = MediaPipeGlassesClassifierAnalyzer(ch);

      final r = await analyzer.analyze(_frame());

      expect(r.isErr, isTrue);
    });
  });
}

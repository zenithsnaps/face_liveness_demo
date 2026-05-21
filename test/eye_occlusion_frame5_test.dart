import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:face_liveness_demo/features/face_liveness/application/utils/eye_occlusion_util.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_metadata.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/rect2d.dart';

/// Standalone verification that the Android rotation fix correctly places
/// EyeOcclusionUtil's ROIs on frame 5 of session 44d7b600 (user wearing
/// reflective brown-tinted sunglasses). Uses a hand-measured face bbox so
/// the test does not depend on ML Kit/MediaPipe.
///
/// The fix is verified by ROI symmetry: with the original double-rotation
/// bug, Sat L/R was 141 / 14.5 on this session (per the device screenshot)
/// — clearly asymmetric, indicating ROIs landed on unrelated regions.
/// With the fix, L and R values should be close to each other because both
/// ROIs land on the same kind of region (the two lenses).
///
/// combinedScore on this particular frame stays at 0.0 because the lenses
/// are brown-tinted (lens-center pixel R≫G≫B → Sat≈170) and the ROI
/// percentages integrate substantial surrounding skin, diluting the
/// dark-lens signal below the bucket thresholds. That is an algorithm-
/// tuning concern separate from the rotation bug fix.
Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frame5 ROI is symmetric after rotation fix', () async {
    final jpegBytes = await File('test/frame5.jpg').readAsBytes();
    final codec = await ui.instantiateImageCodec(jpegBytes);
    final image = (await codec.getNextFrame()).image;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(byteData, isNotNull);
    final rgba = byteData!.buffer.asUint8List();
    final w = image.width;
    final h = image.height;

    // Visually measured face bbox in the 480×720 portrait image. The ROI
    // percentages in EyeOcclusionUtil (eyes at 30–46% of bbox height,
    // cheeks at 58–76%) assume a "full face" bbox spanning forehead → chin,
    // so the top of the bbox is the hairline/forehead, not the eyebrows.
    //  - forehead at ~y=200, chin at ~y=540  → height = 340
    //  - 30%·340 + 200 = 302 ; 46%·340 + 200 = 356  → eye row lands on lens
    //  - 58%·340 + 200 = 397 ; 76%·340 + 200 = 458  → cheek row lands on skin
    final faceBox = Rect2D.fromLTRB(80, 200, 425, 540);

    final frame = FrameData(
      bytes: rgba,
      metadata: FrameMetadata(
        width: w,
        height: h,
        rotationDegrees: 0,
        format: FramePixelFormat.rgba8888,
        timestampMicros: 0,
      ),
    );

    // Point-probe the dead center of each lens (visually estimated) to learn
    // what the lens core pixels actually look like. The ROI integrates a much
    // larger area that bleeds into skin/frame, so this dead-center probe is
    // closer to "pure lens material" than the ROI average.
    int pixelAt(int x, int y, int channel) => rgba[4 * (y * w + x) + channel];
    void probePoint(String label, int x, int y) {
      // ignore: avoid_print
      print('$label ($x,$y): '
          'R=${pixelAt(x, y, 0)} '
          'G=${pixelAt(x, y, 1)} '
          'B=${pixelAt(x, y, 2)}');
    }
    probePoint('leftLensCenter ', 195, 325);
    probePoint('rightLensCenter', 305, 325);
    probePoint('leftCheekCenter', 175, 430);
    probePoint('rightCheekCenter', 320, 430);

    final evidence = EyeOcclusionUtil.detect(frame: frame, faceBox: faceBox);

    // Probe the actual mean RGB of each ROI so we can sanity-check that ROIs
    // land on the lens (low+equal R/G/B) and on cheek skin (mid+slightly
    // pink R>G>B). Mirrors the ROI math inside EyeOcclusionUtil.
    final fw = faceBox.width;
    final fh = faceBox.height;
    final roiList = <(String, Rect2D)>[
      (
        'leftEye',
        Rect2D.fromLTRB(
          faceBox.left + fw * 0.16,
          faceBox.top + fh * 0.30,
          faceBox.left + fw * 0.44,
          faceBox.top + fh * 0.46,
        ),
      ),
      (
        'rightEye',
        Rect2D.fromLTRB(
          faceBox.left + fw * 0.56,
          faceBox.top + fh * 0.30,
          faceBox.left + fw * 0.84,
          faceBox.top + fh * 0.46,
        ),
      ),
      (
        'leftCheek',
        Rect2D.fromLTRB(
          faceBox.left + fw * 0.18,
          faceBox.top + fh * 0.58,
          faceBox.left + fw * 0.43,
          faceBox.top + fh * 0.76,
        ),
      ),
      (
        'rightCheek',
        Rect2D.fromLTRB(
          faceBox.left + fw * 0.57,
          faceBox.top + fh * 0.58,
          faceBox.left + fw * 0.82,
          faceBox.top + fh * 0.76,
        ),
      ),
    ];
    for (final (name, r) in roiList) {
      var sumR = 0, sumG = 0, sumB = 0, count = 0;
      final l = r.left.floor(), t = r.top.floor();
      final rt = r.right.ceil(), bt = r.bottom.ceil();
      for (var yy = t; yy < bt; yy++) {
        for (var xx = l; xx < rt; xx++) {
          final i = 4 * (yy * w + xx);
          sumR += rgba[i];
          sumG += rgba[i + 1];
          sumB += rgba[i + 2];
          count++;
        }
      }
      // ignore: avoid_print
      print('$name @($l,$t)-($rt,$bt): '
          'R=${(sumR / count).toStringAsFixed(1)} '
          'G=${(sumG / count).toStringAsFixed(1)} '
          'B=${(sumB / count).toStringAsFixed(1)}');
    }

    // Print everything so it shows up in `flutter test` stdout.
    // ignore: avoid_print
    print('image:           ${w}x$h');
    // ignore: avoid_print
    print('faceBox:         $faceBox');
    // ignore: avoid_print
    print('referenceLum:    ${evidence.referenceLuminance.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('lum L/R:         '
        '${evidence.leftLumRatio.toStringAsFixed(3)} / '
        '${evidence.rightLumRatio.toStringAsFixed(3)}');
    // ignore: avoid_print
    print('std L/R:         '
        '${evidence.leftStdDev.toStringAsFixed(2)} / '
        '${evidence.rightStdDev.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('sat L/R:         '
        '${evidence.leftSaturation.toStringAsFixed(2)} / '
        '${evidence.rightSaturation.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('score L/R:       '
        '${evidence.leftScore.toStringAsFixed(2)} / '
        '${evidence.rightScore.toStringAsFixed(2)}');
    // ignore: avoid_print
    print('combinedScore:   ${evidence.combinedScore.toStringAsFixed(3)}');
    // ignore: avoid_print
    print('occluded:        ${evidence.occluded}');

    // Rotation-fix proof: both eye ROIs land on the lens region, so their
    // pixel stats must be close to each other. Under the old double-rotation
    // bug, Sat L/R was 141 / 14.5 on this session — clearly asymmetric.
    expect(
      (evidence.leftLumRatio - evidence.rightLumRatio).abs(),
      lessThan(0.15),
      reason: 'L/R lum ratios should be symmetric when both ROIs land on lens',
    );
    expect(
      (evidence.leftSaturation - evidence.rightSaturation).abs(),
      lessThan(30.0),
      reason:
          'L/R saturation should be symmetric when both ROIs land on lens '
          '(was 141 vs 14.5 — diff 126 — under the rotation bug)',
    );
    expect(
      (evidence.leftStdDev - evidence.rightStdDev).abs(),
      lessThan(15.0),
      reason: 'L/R stdDev should be symmetric when both ROIs land on lens',
    );

    // With stdDev signal disabled (per user request — human eye texture is
    // too noisy to be a reliable signal) and the current relaxed sat=130:
    //   Lum 0.66 > lumRatioPass=0.55 → 0
    //   Sat 122 < saturationPass=130 → +0.15 (pass bucket)
    //   stdDev disabled → +0.00
    // combinedScore = 0.15 → below blockScore=0.30 → NOT occluded.
    // This frame's warm-tinted sunglasses are now under-flagged; catching
    // them would require either relaxing lumRatioPass (risks false-positives
    // on natural eye shadow) or adding a different color signal (e.g. sat
    // delta vs cheek, or hue similarity).
    expect(evidence.combinedScore, closeTo(0.15, 0.01));
    expect(evidence.occluded, isFalse);
  });
}

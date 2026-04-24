import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as mlkit;

import '../../../../core/result.dart';
import '../../domain/entities/eye_regions.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/eye_contour_analyzer.dart';
import '../../domain/value_objects/point2d.dart';
import '../../domain/value_objects/rect2d.dart';

/// Post-capture-only ML Kit detector with contours enabled.
///
/// Accepts a [FrameData] with RGBA8888 bytes (as produced by [JpegFrameDecoder])
/// and converts to BGRA8888 before passing to ML Kit via [InputImage.fromBytes].
/// This avoids the EXIF-rotation issue that arises when using
/// [InputImage.fromFilePath] — the captured JPEG may carry an orientation tag
/// that ML Kit's native layer ignores, resulting in a rotated/undetectable face.
class MlKitEyeContourAnalyzer implements EyeContourAnalyzer {
  final mlkit.FaceDetector _detector = mlkit.FaceDetector(
    options: mlkit.FaceDetectorOptions(
      enableClassification: false,
      enableTracking: false,
      enableLandmarks: true,
      enableContours: true,
      performanceMode: mlkit.FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  @override
  Future<Result<EyeRegions?, AnalyzerError>> analyze(FrameData frame) async {
    try {
      final w = frame.width;
      final h = frame.height;
      final rgba = frame.bytes is Uint8List
          ? frame.bytes as Uint8List
          : Uint8List.fromList(frame.bytes);

      // ML Kit expects BGRA8888 (R and B swapped relative to our RGBA source).
      final bgra = _rgbaToBgra(rgba);

      final input = mlkit.InputImage.fromBytes(
        bytes: bgra,
        metadata: mlkit.InputImageMetadata(
          size: Size(w.toDouble(), h.toDouble()),
          rotation: mlkit.InputImageRotation.rotation0deg,
          format: mlkit.InputImageFormat.bgra8888,
          bytesPerRow: w * 4,
        ),
      );

      final faces = await _detector.processImage(input);
      if (faces.isEmpty) return const Ok(null);

      // When multiple faces sneak in, pick the largest.
      final face = faces.reduce((a, b) =>
          a.boundingBox.width * a.boundingBox.height >=
                  b.boundingBox.width * b.boundingBox.height
              ? a
              : b);
      return Ok(_map(face));
    } catch (e) {
      return Err(AnalyzerError('ML Kit eye contour detection failed', cause: e));
    }
  }

  /// In-place RGBA→BGRA channel swap (swap R at i+0 with B at i+2 per pixel).
  Uint8List _rgbaToBgra(Uint8List rgba) {
    final bgra = Uint8List.fromList(rgba);
    for (var i = 0; i < bgra.length - 3; i += 4) {
      final r = bgra[i];
      bgra[i] = bgra[i + 2];
      bgra[i + 2] = r;
    }
    return bgra;
  }

  EyeRegions _map(mlkit.Face face) {
    final box = face.boundingBox;
    final faceBox = Rect2D.fromLTRB(
      box.left.toDouble(),
      box.top.toDouble(),
      box.right.toDouble(),
      box.bottom.toDouble(),
    );

    List<Point2D> mapContour(mlkit.FaceContourType type) {
      final contour = face.contours[type];
      if (contour == null) return const [];
      return contour.points
          .map((p) => Point2D(p.x.toDouble(), p.y.toDouble()))
          .toList();
    }

    Point2D? mapLandmark(mlkit.FaceLandmarkType type) {
      final lm = face.landmarks[type];
      if (lm == null) return null;
      return Point2D(lm.position.x.toDouble(), lm.position.y.toDouble());
    }

    return EyeRegions(
      leftEye: mapContour(mlkit.FaceContourType.leftEye),
      rightEye: mapContour(mlkit.FaceContourType.rightEye),
      leftCheek: mapLandmark(mlkit.FaceLandmarkType.leftCheek),
      rightCheek: mapLandmark(mlkit.FaceLandmarkType.rightCheek),
      faceBox: faceBox,
    );
  }

  @override
  Future<void> dispose() async {
    await _detector.close();
  }
}

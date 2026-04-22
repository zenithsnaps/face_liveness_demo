import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart' as mlkit;

import '../../../../core/result.dart';
import '../../domain/entities/face_snapshot.dart' as domain;
import '../../domain/entities/frame_data.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/repositories/face_analyzer.dart';
import '../../domain/value_objects/confidence.dart';
import '../../domain/value_objects/euler_angles.dart';
import '../../domain/value_objects/point2d.dart';
import '../../domain/value_objects/rect2d.dart';

/// Implementation of [FaceAnalyzer] backed by Google ML Kit Face Detection.
///
/// The pure-Dart domain interface takes a `FrameData` because that is what is
/// portable. ML Kit, however, needs an `InputImage` with platform-specific
/// metadata (rotation, byte layout). To avoid re-decoding, the presentation
/// layer stages the ready-made `InputImage` via [setPendingInputImage] right
/// before calling `analyze`. This is infrastructure-internal glue and stays
/// out of domain/application.
class MlKitFaceAnalyzer implements FaceAnalyzer {
  final mlkit.FaceDetector _detector = mlkit.FaceDetector(
    options: mlkit.FaceDetectorOptions(
      enableClassification: true,
      enableTracking: false,
      enableLandmarks: true,
      enableContours: false,
      performanceMode: mlkit.FaceDetectorMode.fast,
      minFaceSize: 0.15,
    ),
  );

  mlkit.InputImage? _pendingImage;

  void setPendingInputImage(mlkit.InputImage image) {
    _pendingImage = image;
  }

  @override
  Future<Result<domain.FaceSnapshot?, AnalyzerError>> analyze(FrameData frame) async {
    final input = _pendingImage;
    _pendingImage = null;
    if (input == null) {
      return const Err(AnalyzerError('No InputImage was staged before analyze()'));
    }
    try {
      final faces = await _detector.processImage(input);
      if (faces.isEmpty) return const Ok(null);
      if (faces.length > 1) {
        return const Err(AnalyzerError('multipleFaces'));
      }
      return Ok(_map(faces.first));
    } catch (e) {
      return Err(AnalyzerError('ML Kit face detection failed', cause: e));
    }
  }

  domain.FaceSnapshot _map(mlkit.Face face) {
    final box = face.boundingBox;
    final landmarks = <domain.FaceLandmarkType, Point2D>{};
    for (final entry in face.landmarks.entries) {
      final type = _mapLandmarkType(entry.key);
      final lm = entry.value;
      if (type != null && lm != null) {
        landmarks[type] = Point2D(
          lm.position.x.toDouble(),
          lm.position.y.toDouble(),
        );
      }
    }

    return domain.FaceSnapshot(
      boundingBox: Rect2D.fromLTRB(
        box.left,
        box.top,
        box.right,
        box.bottom,
      ),
      headPose: EulerAngles(
        yaw: face.headEulerAngleY ?? 0,
        pitch: face.headEulerAngleX ?? 0,
        roll: face.headEulerAngleZ ?? 0,
      ),
      smilingProbability: Confidence.clamped(face.smilingProbability ?? 0),
      leftEyeOpenProbability:
          Confidence.clamped(face.leftEyeOpenProbability ?? 0),
      rightEyeOpenProbability:
          Confidence.clamped(face.rightEyeOpenProbability ?? 0),
      landmarks: landmarks,
      landmarkVisibility: const {},
    );
  }

  domain.FaceLandmarkType? _mapLandmarkType(mlkit.FaceLandmarkType type) {
    return switch (type) {
      mlkit.FaceLandmarkType.leftEye => domain.FaceLandmarkType.leftEye,
      mlkit.FaceLandmarkType.rightEye => domain.FaceLandmarkType.rightEye,
      mlkit.FaceLandmarkType.noseBase => domain.FaceLandmarkType.noseBase,
      mlkit.FaceLandmarkType.leftMouth => domain.FaceLandmarkType.mouthLeft,
      mlkit.FaceLandmarkType.rightMouth => domain.FaceLandmarkType.mouthRight,
      mlkit.FaceLandmarkType.bottomMouth => domain.FaceLandmarkType.mouthBottom,
      mlkit.FaceLandmarkType.leftCheek => domain.FaceLandmarkType.leftCheek,
      mlkit.FaceLandmarkType.rightCheek => domain.FaceLandmarkType.rightCheek,
      mlkit.FaceLandmarkType.leftEar => domain.FaceLandmarkType.leftEar,
      mlkit.FaceLandmarkType.rightEar => domain.FaceLandmarkType.rightEar,
    };
  }

  @override
  Future<void> dispose() async {
    await _detector.close();
  }
}

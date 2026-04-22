import 'package:face_liveness_demo/features/face_liveness/domain/entities/face_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/confidence.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/euler_angles.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/rect2d.dart';

/// Pure-Dart helper that builds a plausible [FaceSnapshot] centered in an
/// oval of the given width. Defaults are "all gates would pass".
FaceSnapshot buildFaceSnapshot({
  double widthRatio = 0.92,
  double ovalWidth = 400,
  double ovalHeight = 600,
  double ovalLeft = 40,
  double ovalTop = 100,
  double smile = 0.0,
  double leftEye = 1.0,
  double rightEye = 1.0,
  double yaw = 0,
  double pitch = 0,
  double roll = 0,
  Map<FaceLandmarkType, Confidence> landmarkVisibility = const {},
}) {
  final w = ovalWidth * widthRatio;
  final h = ovalHeight * widthRatio;
  final centerX = ovalLeft + ovalWidth / 2;
  final centerY = ovalTop + ovalHeight / 2;
  final bbox = Rect2D.fromLTWH(
    centerX - w / 2,
    centerY - h / 2,
    w,
    h,
  );
  return FaceSnapshot(
    boundingBox: bbox,
    headPose: EulerAngles(yaw: yaw, pitch: pitch, roll: roll),
    smilingProbability: Confidence.clamped(smile),
    leftEyeOpenProbability: Confidence.clamped(leftEye),
    rightEyeOpenProbability: Confidence.clamped(rightEye),
    landmarkVisibility: landmarkVisibility,
  );
}

Rect2D defaultOvalGuide({
  double left = 40,
  double top = 100,
  double width = 400,
  double height = 600,
}) =>
    Rect2D.fromLTWH(left, top, width, height);

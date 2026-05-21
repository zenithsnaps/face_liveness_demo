import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/entities/face_detection.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/frame_metadata.dart';
import '../../domain/repositories/hand_analyzer.dart';
import '../../domain/value_objects/rect2d.dart';
import '../../infrastructure/mediapipe/mediapipe_face_detection_analyzer.dart';
import '../../infrastructure/platform_channels/mediapipe_channel.dart';
import '../utils/eye_occlusion_util.dart';
import 'pre_capture_score_thresholds.dart';
import 'score_frame.dart';

/// Per-frame scoring stage of the pre-capture batch.
///
/// Decodes the stream frame into an upright RGBA8888 via native, then runs in
/// parallel:
///   - MediaPipe face detection → faceScore + faceBox
///   - MediaPipe hand landmarker → handScore
///
/// The faceBox of the highest-scoring face is reused to compute
/// EyeOcclusionUtil pixel analysis (sunglasses). No ML Kit eye contour call
/// is needed — the production sunglasses algorithm derives eye/cheek regions
/// from face bbox geometry alone.
///
/// Returns null when the upright decode fails or any analyzer errors — the
/// caller should skip this frame rather than admit it with partial data.
class ScoreFrameAnalyzer {
  final MediaPipeChannel _channel;
  final MediaPipeFaceDetectionAnalyzer _face;
  final HandAnalyzer _hand;

  ScoreFrameAnalyzer({
    required MediaPipeChannel channel,
    required MediaPipeFaceDetectionAnalyzer face,
    required HandAnalyzer hand,
  })  : _channel = channel,
        _face = face,
        _hand = hand;

  /// [mlKitFaceBox], when supplied, is preferred over MediaPipe's face bbox
  /// for the eye-occlusion ROI geometry. ML Kit returns a tighter face box
  /// (from eyebrows/upper-cheekbone down to chin) that aligns with the
  /// production-tuned ROI percentages (eyes at 30-46% of bbox height).
  /// MediaPipe's BlazeFace bbox often extends up into the forehead/hair, so
  /// the same 30-46% range falls on skin instead of the lens.
  Future<ScoreFrame?> analyze(
    FrameData streamFrame,
    PreCaptureScoreThresholds thresholds, {
    Rect2D? mlKitFaceBox,
  }) async {
    // iOS pre-rotation correction: AVFoundation rotates the streamed buffer
    // to match `connection.videoOrientation = .portrait` (set by the camera
    // plugin), so the bytes are already display-upright even though the
    // FrameData's `rotationDegrees` carries `sensorOrientation`. Without
    // overriding here, downstream native code would rotate again, producing
    // a sideways image. Face bbox + EyeOcclusionUtil's geometric ROIs would
    // then sit on cheek/forehead instead of the eyes → per-eye scores stuck
    // at 0. Override rotation=0 to keep all analyzers in the buffer's true
    // coordinate space.
    final analysisFrame = Platform.isIOS && streamFrame.rotationDegrees != 0
        ? FrameData(
            bytes: streamFrame.bytes,
            metadata: FrameMetadata(
              width: streamFrame.width,
              height: streamFrame.height,
              rotationDegrees: 0,
              format: streamFrame.format,
              timestampMicros: streamFrame.timestampMicros,
            ),
          )
        : streamFrame;

    final upright = await _toUpright(analysisFrame);
    if (upright == null) return null;

    final faceFuture = _face.analyze(upright);
    final handFuture = _hand.analyze(upright);

    final faceResult = await faceFuture;
    final handResult = await handFuture;

    if (faceResult.isErr || handResult.isErr) return null;

    final faces = faceResult.okOrNull!;
    FaceDetection? bestFace;
    for (final f in faces) {
      if (bestFace == null || f.score.value > bestFace.score.value) {
        bestFace = f;
      }
    }
    final faceScore = bestFace?.score.value ?? 0.0;

    final hands = handResult.okOrNull!;
    final handScore = hands.isEmpty
        ? 0.0
        : hands.map((h) => h.confidence.value).reduce(math.max);
    final handCount = hands
        .where((h) => h.confidence.value >= thresholds.handBlockThreshold)
        .length;

    // ML Kit returns face.boundingBox in display-upright (rotation-corrected)
    // coordinates because InputImageConverter always passes a non-zero
    // InputImageRotation when building the InputImage — ML Kit then virtually
    // rotates the buffer and reports the bbox against the upright image.
    // bestFace?.boundingBox is also upright-relative because MediaPipe runs on
    // the `upright` frame above. Both already match the coord space that
    // EyeOcclusionUtil reads pixels from, so no transform is needed.
    final occlusionBox = mlKitFaceBox ?? bestFace?.boundingBox;
    double sunglassesScore = 0.0;
    var evidence = occlusionBox != null
        ? EyeOcclusionUtil.detect(
            frame: upright,
            faceBox: occlusionBox,
            thresholds: thresholds.eyeThresholds,
          )
        : null;
    if (evidence != null) {
      sunglassesScore = evidence.combinedScore;
    }

    return ScoreFrame(
      faceScore: faceScore,
      handScore: handScore,
      handCount: handCount,
      sunglassesScore: sunglassesScore,
      eyeEvidence: evidence,
      // Keep the *original* sensor-orientation frame for JPEG encoding —
      // native FrameDecoder.decodeUprightBitmap will rotate it correctly in a
      // single pass. Re-encoding the already-rotated RGBA via two round-trips
      // through native dropped the rotation tag on some devices and produced
      // a JPEG tilted 90°. Pixel analysis above used `upright`, which is
      // still correct; we just don't persist it on the slot.
      frame: streamFrame,
    );
  }

  Future<FrameData?> _toUpright(FrameData frame) async {
    if (frame.format == FramePixelFormat.rgba8888 &&
        frame.rotationDegrees == 0) {
      return frame;
    }
    final raw = await _channel.decodeUprightRgba(frame);
    if (raw == null) return null;
    final bytesRaw = raw['bytes'];
    final width = (raw['width'] as num?)?.toInt();
    final height = (raw['height'] as num?)?.toInt();
    if (bytesRaw == null || width == null || height == null) return null;
    final Uint8List bytes = bytesRaw is Uint8List
        ? bytesRaw
        : Uint8List.fromList((bytesRaw as List).cast<int>());
    return FrameData(
      bytes: bytes,
      metadata: FrameMetadata(
        width: width,
        height: height,
        rotationDegrees: 0,
        format: FramePixelFormat.rgba8888,
        timestampMicros: frame.timestampMicros,
      ),
    );
  }
}

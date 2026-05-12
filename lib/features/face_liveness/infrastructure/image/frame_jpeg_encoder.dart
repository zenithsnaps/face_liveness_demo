import 'dart:io' show Platform;

import 'package:path_provider/path_provider.dart';

import '../../domain/entities/frame_data.dart';
import '../../domain/entities/frame_metadata.dart';
import '../platform_channels/mediapipe_channel.dart';

/// Encodes a stream [FrameData] as an upright JPEG written to a temp file.
///
/// Delegates to native (`MediaPipeChannel.encodeFrameToJpeg`) which reuses the
/// same upright-bitmap path the post-capture JPEG decoder relies on. Returns
/// the absolute path on success or null on failure.
///
/// Output path contract matches what `camera.takePicture()` produced
/// (a regular .jpg file on disk), so `ResultScreen`, `precacheImage`, and the
/// Supabase upload path keep working unchanged.
///
/// **iOS rotation note**: AVFoundation rotates the streamed buffer to match
/// `connection.videoOrientation = .portrait` (set by the camera plugin), so
/// on iOS the bytes are already display-upright. We override
/// `rotationDegrees` to 0 before encoding to prevent the native side from
/// applying a second rotation that would tilt the JPEG by 90°. Android's
/// Camera2 path delivers raw sensor-orientation bytes and needs the actual
/// `sensorOrientation` to rotate to upright.
class FrameJpegEncoder {
  final MediaPipeChannel _channel;

  FrameJpegEncoder(this._channel);

  Future<String?> encodeToTempFile(FrameData frame, {int quality = 90}) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final outPath = '${dir.path}/liveness_capture_$stamp.jpg';
    final framed = Platform.isIOS && frame.rotationDegrees != 0
        ? FrameData(
            bytes: frame.bytes,
            metadata: FrameMetadata(
              width: frame.width,
              height: frame.height,
              rotationDegrees: 0,
              format: frame.format,
              timestampMicros: frame.timestampMicros,
            ),
          )
        : frame;
    return _channel.encodeFrameToJpeg(framed, outPath: outPath, quality: quality);
  }
}

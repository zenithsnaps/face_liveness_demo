import 'dart:io';
import 'dart:ui' as ui;

import '../../domain/entities/frame_data.dart';
import '../../domain/entities/frame_metadata.dart';

/// Decodes a JPEG file (from [camera.takePicture]) into a [FrameData] with
/// [FramePixelFormat.rgba8888].
///
/// [camera.takePicture] returns an already-rotated JPEG, so rotationDegrees = 0.
/// Skia's codec decodes to raw RGBA in ~50-100 ms for a typical camera JPEG.
class JpegFrameDecoder {
  const JpegFrameDecoder._();

  static Future<FrameData> decode(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('Failed to decode JPEG to RGBA: $path');
    }

    final width = image.width;
    final height = image.height;
    image.dispose();

    return FrameData(
      bytes: byteData.buffer.asUint8List(),
      metadata: FrameMetadata(
        width: width,
        height: height,
        rotationDegrees: 0,
        format: FramePixelFormat.rgba8888,
        timestampMicros: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }
}

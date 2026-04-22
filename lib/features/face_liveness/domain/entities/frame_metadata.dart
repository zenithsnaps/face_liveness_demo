import 'package:meta/meta.dart';

/// Pure-Dart image-format enum. Infrastructure maps these to
/// platform-specific formats (ML Kit / MediaPipe).
enum FramePixelFormat {
  yuv420,
  bgra8888,
  nv21,
  rgba8888,
}

@immutable
class FrameMetadata {
  final int width;
  final int height;
  /// Clockwise rotation to apply to reach upright, in degrees (0/90/180/270).
  final int rotationDegrees;
  final FramePixelFormat format;
  final int timestampMicros;

  const FrameMetadata({
    required this.width,
    required this.height,
    required this.rotationDegrees,
    required this.format,
    required this.timestampMicros,
  })  : assert(width > 0),
        assert(height > 0),
        assert(rotationDegrees == 0 ||
            rotationDegrees == 90 ||
            rotationDegrees == 180 ||
            rotationDegrees == 270);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FrameMetadata &&
          other.width == width &&
          other.height == height &&
          other.rotationDegrees == rotationDegrees &&
          other.format == format &&
          other.timestampMicros == timestampMicros);

  @override
  int get hashCode =>
      Object.hash(width, height, rotationDegrees, format, timestampMicros);
}

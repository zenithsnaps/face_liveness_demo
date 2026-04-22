import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../domain/entities/frame_data.dart';
import '../../domain/entities/frame_metadata.dart';

/// Converts a [CameraImage] into the pair of representations the rest of the
/// app needs:
///   - [FrameData] for the domain layer + MediaPipe platform channel (raw bytes)
///   - [InputImage] for ML Kit's `FaceDetector`
///
/// ML Kit's Android path requires NV21-packed bytes; its iOS path requires
/// BGRA planes. This converter hides that divergence.
class InputImageConverter {
  const InputImageConverter();

  FrameData toFrameData(CameraImage image, int sensorOrientation) {
    final bytes = _flattenPlanes(image);
    return FrameData(
      bytes: bytes,
      metadata: FrameMetadata(
        width: image.width,
        height: image.height,
        rotationDegrees: sensorOrientation,
        format: _mapFormat(image.format.group),
        timestampMicros: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }

  InputImage? toMlKitInputImage(
    CameraImage image,
    CameraDescription camera,
    int deviceOrientationDegrees,
  ) {
    final rotation = _rotationForMlKit(
      camera: camera,
      deviceOrientationDegrees: deviceOrientationDegrees,
    );
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // ML Kit on Android expects NV21; on iOS expects BGRA8888.
    if (format != InputImageFormat.nv21 &&
        format != InputImageFormat.bgra8888 &&
        format != InputImageFormat.yuv_420_888 &&
        format != InputImageFormat.yv12) {
      return null;
    }

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: _flattenPlanesBytes(image),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationForMlKit({
    required CameraDescription camera,
    required int deviceOrientationDegrees,
  }) {
    final sensor = camera.sensorOrientation;
    int rotation;
    if (camera.lensDirection == CameraLensDirection.front) {
      rotation = (sensor + deviceOrientationDegrees) % 360;
    } else {
      rotation = (sensor - deviceOrientationDegrees + 360) % 360;
    }
    return switch (rotation) {
      0 => InputImageRotation.rotation0deg,
      90 => InputImageRotation.rotation90deg,
      180 => InputImageRotation.rotation180deg,
      270 => InputImageRotation.rotation270deg,
      _ => null,
    };
  }

  FramePixelFormat _mapFormat(ImageFormatGroup group) {
    return switch (group) {
      ImageFormatGroup.yuv420 => FramePixelFormat.yuv420,
      ImageFormatGroup.bgra8888 => FramePixelFormat.bgra8888,
      ImageFormatGroup.nv21 => FramePixelFormat.nv21,
      _ => FramePixelFormat.yuv420,
    };
  }

  List<int> _flattenPlanes(CameraImage image) {
    return _flattenPlanesBytes(image);
  }

  Uint8List _flattenPlanesBytes(CameraImage image) {
    final totalBytes = image.planes.fold<int>(
      0,
      (sum, plane) => sum + plane.bytes.length,
    );
    final out = Uint8List(totalBytes);
    var offset = 0;
    for (final plane in image.planes) {
      out.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }
    return out;
  }
}


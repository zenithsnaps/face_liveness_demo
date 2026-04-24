import 'dart:async';
import 'dart:io' show Platform;

import 'package:camera/camera.dart';

/// Owns the [CameraController] and exposes the raw `CameraImage` stream.
///
/// Callers wrap this to produce domain FrameData and ML Kit InputImage.
/// Lifecycle (per spec §Camera lifecycle):
///  - `inactive` / `paused` → `stop()` then `dispose()`
///  - `resumed` → `initialize()` + `startStream()`
///  - Always stop the stream before disposing the controller (iOS crash).
class CameraFrameSource {
  CameraController? _controller;
  CameraDescription? _camera;
  bool _streaming = false;

  CameraController? get controller => _controller;
  CameraDescription? get currentCamera => _camera;
  bool get isStreaming => _streaming;

  Future<void> initialize() async {
    // Tear down any previous session before creating a new controller.
    // Without this, _streaming stays true on retry and startStream() is a no-op.
    await stopStream();
    final old = _controller;
    _controller = null;
    await old?.dispose();

    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available');
    }
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camera = front;

    // Android: NV21 is the format ML Kit prefers. iOS: BGRA8888.
    final format = Platform.isIOS
        ? ImageFormatGroup.bgra8888
        : ImageFormatGroup.nv21;

    final controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: format,
    );
    await controller.initialize();
    // Disable flash. On iOS, the default `auto` mode uses the screen as a
    // selfie flash on the front camera — that's the white screen flash users
    // see at the moment of capture. We never want it for a liveness check.
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {
      // Some devices/cameras don't support setFlashMode; ignore.
    }
    _controller = controller;
  }

  Future<void> startStream(Function(CameraImage image) onImage) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('Camera not initialized');
    }
    if (_streaming) return;
    await controller.startImageStream(onImage);
    _streaming = true;
  }

  Future<void> stopStream() async {
    final controller = _controller;
    if (controller == null || !_streaming) return;
    try {
      await controller.stopImageStream();
    } catch (_) {
      // The camera plugin occasionally throws here if the stream has already
      // been torn down — ignore, it's safe.
    } finally {
      _streaming = false;
    }
  }

  Future<String?> takePicture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    // Must stop streaming before taking a picture on some devices.
    await stopStream();
    try {
      final file = await controller.takePicture();
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await stopStream();
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}

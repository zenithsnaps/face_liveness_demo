import 'package:flutter/services.dart';

import '../../../../core/app_constants.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/frame_metadata.dart';

/// Thin wrapper over a single `MethodChannel` used to call MediaPipe on native.
///
/// Method contract (mirrored in Kotlin + Swift):
///   - `initialize` — load models from bundled assets
///   - `detectHands(frame)` → `List<Map>`
///   - `detectObjects(frame)` → `List<Map>`
///   - `detectFaces(frame)` → `List<Map>` — [{confidence, bbox}] per face
///   - `detectFaceLandmarks(frame)` → `Map` — {found, landmarks: [[x,y,z,vis,pres]×478]}
///   - `dispose`
///
/// Frame is serialized as:
///   {
///     bytes: Uint8List,
///     width: int,
///     height: int,
///     rotation: int,     // 0/90/180/270
///     format: String,    // 'yuv420' | 'nv21' | 'bgra8888' | 'rgba8888'
///   }
class MediaPipeChannel {
  static const _channel = MethodChannel(AppConstants.mediaPipeChannelName);
  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    await _channel.invokeMethod<void>('initialize');
    _initialized = true;
  }

  Future<List<Map<String, Object?>>> detectHands(FrameData frame) async {
    final raw = await _channel.invokeListMethod<Object?>(
      'detectHands',
      _encodeFrame(frame),
    );
    return _decodeMapList(raw);
  }

  Future<List<Map<String, Object?>>> detectObjects(FrameData frame) async {
    final raw = await _channel.invokeListMethod<Object?>(
      'detectObjects',
      _encodeFrame(frame),
    );
    return _decodeMapList(raw);
  }

  Future<List<Map<String, Object?>>> detectFaces(FrameData frame) async {
    final raw = await _channel.invokeListMethod<Object?>(
      'detectFaces',
      _encodeFrame(frame),
    );
    return _decodeMapList(raw);
  }

  /// Returns `{found: bool, landmarks: [[x,y,z,visibility,presence]×478]}`.
  /// `found: false` when the model detected no face in the frame.
  Future<Map<String, Object?>> detectFaceLandmarks(FrameData frame) async {
    final raw = await _channel.invokeMapMethod<String, Object?>(
      'detectFaceLandmarks',
      _encodeFrame(frame),
    );
    return raw ?? const {};
  }

  Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (_) {
      // ignore — native may already be torn down.
    }
  }

  Map<String, Object?> _encodeFrame(FrameData frame) {
    final bytes = frame.bytes is Uint8List
        ? frame.bytes as Uint8List
        : Uint8List.fromList(frame.bytes);
    return {
      'bytes': bytes,
      'width': frame.width,
      'height': frame.height,
      'rotation': frame.rotationDegrees,
      'format': _formatString(frame.format),
    };
  }

  String _formatString(FramePixelFormat f) => switch (f) {
        FramePixelFormat.yuv420 => 'yuv420',
        FramePixelFormat.nv21 => 'nv21',
        FramePixelFormat.bgra8888 => 'bgra8888',
        FramePixelFormat.rgba8888 => 'rgba8888',
      };

  List<Map<String, Object?>> _decodeMapList(List<Object?>? raw) {
    if (raw == null) return const [];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList(growable: false);
  }
}

import 'package:meta/meta.dart';

import 'frame_metadata.dart';

/// Carries a raw image frame plus its metadata across the layer boundary.
///
/// The [bytes] field is typed as `List<int>` (not `Uint8List`) to keep the
/// domain free of `dart:typed_data` — infrastructure will cast/copy on the
/// way in and on the way out.
@immutable
class FrameData {
  final List<int> bytes;
  final FrameMetadata metadata;

  const FrameData({required this.bytes, required this.metadata});

  int get width => metadata.width;
  int get height => metadata.height;
  int get rotationDegrees => metadata.rotationDegrees;
  FramePixelFormat get format => metadata.format;
  int get timestampMicros => metadata.timestampMicros;
}

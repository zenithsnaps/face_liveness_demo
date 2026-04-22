import 'package:meta/meta.dart';

import '../value_objects/confidence.dart';
import '../value_objects/rect2d.dart';

/// A generic detected object (phone / cup / card / etc) in a frame.
@immutable
class ObjectSnapshot {
  final Rect2D boundingBox;
  final String label;
  final Confidence confidence;

  const ObjectSnapshot({
    required this.boundingBox,
    required this.label,
    required this.confidence,
  });
}

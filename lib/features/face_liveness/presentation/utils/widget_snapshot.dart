import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Renders the widget tree attached to [key] into a PNG byte array.
/// Returns null if the key has no context or its render object is not a
/// [RenderRepaintBoundary] (e.g. the widget has not been painted yet).
Future<Uint8List?> captureBoundaryPng(
  GlobalKey key, {
  double pixelRatio = 2.0,
}) async {
  final context = key.currentContext;
  if (context == null) return null;

  final ro = context.findRenderObject();
  if (ro is! RenderRepaintBoundary) return null;

  final image = await ro.toImage(pixelRatio: pixelRatio);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return byteData?.buffer.asUint8List();
}

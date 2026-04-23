import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'widget_snapshot.dart';

/// Capture [key]'s RepaintBoundary as PNG and open the system share sheet.
///
/// Pass [context] so iOS can anchor the share popover to the button's position.
/// Without it, iOS 13+ throws PlatformException on iPad and some iPhones.
Future<void> sharePng(
  GlobalKey key, {
  String filename = 'analytics.png',
  BuildContext? context,
}) async {
  final bytes = await captureBoundaryPng(key, pixelRatio: 3.0);
  if (bytes == null) return;
  final file = XFile.fromData(bytes, mimeType: 'image/png', name: filename);

  Rect? shareRect;
  if (context != null && context.mounted) {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      shareRect = box.localToGlobal(Offset.zero) & box.size;
    }
  }

  await Share.shareXFiles([file], sharePositionOrigin: shareRect);
}

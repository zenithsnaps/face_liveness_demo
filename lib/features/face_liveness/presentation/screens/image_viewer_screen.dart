import 'package:flutter/material.dart';

class ImageViewerScreen extends StatelessWidget {
  final String url;
  final String heroTag;

  const ImageViewerScreen({
    super.key,
    required this.url,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: Center(
          child: Hero(
            tag: heroTag,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image,
                  color: Colors.white38,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      );
}

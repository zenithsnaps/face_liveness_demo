import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ring buffer of the most recent realtime MediaPipe face detection scores.
/// `null` entries mean no face was found in that frame.
class FaceScoreSamplesController extends Notifier<List<double?>> {
  static const int maxSamples = 60; // ~2s at 30fps

  @override
  List<double?> build() => const [];

  void add(double? score) {
    final next = [...state, score];
    if (next.length > maxSamples) {
      next.removeRange(0, next.length - maxSamples);
    }
    state = next;
  }

  void clear() => state = const [];
}

final faceScoreSamplesProvider =
    NotifierProvider<FaceScoreSamplesController, List<double?>>(
  FaceScoreSamplesController.new,
);

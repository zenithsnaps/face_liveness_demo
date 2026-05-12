import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../../application/batch/score_frame.dart';
import '../../domain/entities/frame_data.dart';

/// Encodes a frame to a JPEG and returns the file path, or null on failure.
typedef FrameEncoder = Future<String?> Function(FrameData frame);

/// A single captured frame, ready to display on the result screen and persist
/// to Supabase. Bundles the per-frame scoring data with the encoded JPEG path
/// and its position in the session.
@immutable
class CapturedFrame {
  final ScoreFrame score;
  final String jpegPath;
  final int sequence;

  const CapturedFrame({
    required this.score,
    required this.jpegPath,
    required this.sequence,
  });
}

/// One scan session: a fixed-size run of [CapturedFrame]s that share a
/// [groupId]. The face-max frame is the one shown as the main photo at the
/// top of the result screen.
@immutable
class CaptureSession {
  final String groupId;
  final List<CapturedFrame> frames;

  const CaptureSession({required this.groupId, required this.frames});

  CapturedFrame get faceMaxFrame {
    return frames.reduce(
      (a, b) => a.score.faceScore > b.score.faceScore ? a : b,
    );
  }
}

/// Outcome of admitting one [ScoreFrame] into the running session.
sealed class BatchOutcome {
  const BatchOutcome();
}

/// Session is still filling — keep streaming frames.
@immutable
final class BatchAdmitInProgress extends BatchOutcome {
  final int admittedCount;
  const BatchAdmitInProgress(this.admittedCount);
}

/// Session reached the configured target count. [session] holds all the
/// encoded frames in capture order.
@immutable
final class BatchSessionComplete extends BatchOutcome {
  final CaptureSession session;
  const BatchSessionComplete(this.session);
}

/// Stateful coordinator that collects [targetSize] stream frames while the
/// geometry gate is passing, encodes each to a JPEG on disk, and emits the
/// completed session once full.
///
/// Pass/fail is intentionally not a concept here — the result screen shows
/// the captured frames + per-frame metrics for downstream review.
///
/// Not thread-safe; the screen drives admit() from a single drop-when-busy
/// camera loop.
class BatchCaptureCoordinator {
  final FrameEncoder _encode;
  final Uuid _uuid;

  String? _groupId;
  final List<CapturedFrame> _frames = [];

  BatchCaptureCoordinator({
    required FrameEncoder encoder,
    Uuid? uuid,
  })  : _encode = encoder,
        _uuid = uuid ?? const Uuid();

  int get admittedCount => _frames.length;
  String? get groupId => _groupId;

  /// Wipe the running session and delete any partially-encoded JPEGs. Call
  /// when the geometry gate fails so the next admit starts a fresh batch.
  void reset() {
    final pending = List<CapturedFrame>.from(_frames);
    _frames.clear();
    _groupId = null;
    for (final f in pending) {
      // Best-effort cleanup; file might already be gone (e.g. fake paths in
      // tests, or OS swept temp). Swallow the error rather than crash.
      unawaited(File(f.jpegPath).delete().catchError((_) => File(f.jpegPath)));
    }
  }

  /// Admit one analyzed frame. Encodes the JPEG to a temp file and appends
  /// to the running session. When the count reaches [targetSize], returns
  /// [BatchSessionComplete] with the full ordered session; otherwise returns
  /// [BatchAdmitInProgress].
  ///
  /// On encoder failure the frame is silently skipped (admit count does not
  /// advance) so the session still ends up with exactly [targetSize] frames.
  Future<BatchOutcome> admit(ScoreFrame frame, int targetSize) async {
    final jpegPath = await _encode(frame.frame);
    if (jpegPath == null) {
      return BatchAdmitInProgress(_frames.length);
    }
    _groupId ??= _uuid.v4();
    _frames.add(CapturedFrame(
      score: frame,
      jpegPath: jpegPath,
      // Sequence is 1-based so it matches the row label the result screen
      // and Supabase store (sequence column starts at 1, not 0).
      sequence: _frames.length + 1,
    ));
    if (_frames.length < targetSize) {
      return BatchAdmitInProgress(_frames.length);
    }
    final session = CaptureSession(
      groupId: _groupId!,
      frames: List.unmodifiable(_frames),
    );
    _frames.clear();
    _groupId = null;
    return BatchSessionComplete(session);
  }
}


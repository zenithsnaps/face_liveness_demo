import 'package:face_liveness_demo/core/result.dart';
import 'package:face_liveness_demo/features/face_liveness/application/usecases/check_no_eye_occlusion.dart';
import 'package:face_liveness_demo/features/face_liveness/application/usecases/post_capture_checks.dart';
import 'package:face_liveness_demo/features/face_liveness/application/usecases/post_capture_thresholds.dart';
import 'package:face_liveness_demo/features/face_liveness/application/usecases/validate_capture.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/eye_regions.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/face_detection.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/face_snapshot.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_data.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/frame_metadata.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/failures/liveness_failure.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/entities/glasses_evidence.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/repositories/eye_contour_analyzer.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/repositories/glasses_classifier_analyzer.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/confidence.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/value_objects/rect2d.dart';
import 'package:face_liveness_demo/features/face_liveness/infrastructure/mediapipe/mediapipe_face_detection_analyzer.dart';
import 'package:face_liveness_demo/features/face_liveness/infrastructure/platform_channels/mediapipe_channel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../mocks/fake_face_landmarker_analyzer.dart';
import '../../mocks/fake_hand_analyzer.dart';

// --- Fakes ----------------------------------------------------------------

class FakeMediaPipeFaceDetectionAnalyzer extends MediaPipeFaceDetectionAnalyzer {
  Result<List<FaceDetection>, AnalyzerError> nextResult = const Ok([]);

  FakeMediaPipeFaceDetectionAnalyzer() : super(MediaPipeChannel());

  @override
  Future<Result<List<FaceDetection>, AnalyzerError>> analyze(
    FrameData frame,
  ) async =>
      nextResult;
}

class FakeEyeContourAnalyzer implements EyeContourAnalyzer {
  Result<EyeRegions?, AnalyzerError> nextResult = const Ok(null);

  @override
  Future<Result<EyeRegions?, AnalyzerError>> analyze(FrameData frame) async =>
      nextResult;

  @override
  Future<void> dispose() async {}
}

class FakeGlassesClassifierAnalyzer implements GlassesClassifierAnalyzer {
  // Default: no sunglasses (proba 0) so it never blocks unless a test opts in.
  Result<GlassesEvidence, AnalyzerError> nextResult =
      const Ok(GlassesEvidence(sunglassesProba: 0, threshold: 0.5));

  @override
  Future<Result<GlassesEvidence, AnalyzerError>> analyze(
    FrameData frame, {
    Rect2D? faceBox,
  }) async =>
      nextResult;

  @override
  Future<void> dispose() async {}
}

// --- Helpers ---------------------------------------------------------------

const _frame = FrameData(
  bytes: [],
  metadata: FrameMetadata(
    width: 640,
    height: 480,
    rotationDegrees: 0,
    format: FramePixelFormat.rgba8888,
    timestampMicros: 0,
  ),
);

const _goodFace = FaceDetection(
  boundingBox: Rect2D.fromLTWH(100, 100, 200, 250),
  score: Confidence(0.97),
);

const _defaultThresholds = PostCaptureThresholds.defaults;

ValidateCapture _buildUseCase({
  required FakeMediaPipeFaceDetectionAnalyzer faceAnalyzer,
  required FakeHandAnalyzer handAnalyzer,
  required FakeFaceLandmarkerAnalyzer landmarkerAnalyzer,
  FakeEyeContourAnalyzer? eyeContourAnalyzer,
  FakeGlassesClassifierAnalyzer? glassesAnalyzer,
}) {
  return ValidateCapture(
    faceAnalyzer: faceAnalyzer,
    handAnalyzer: handAnalyzer,
    faceLandmarkerAnalyzer: landmarkerAnalyzer,
    eyeContourAnalyzer: eyeContourAnalyzer ?? FakeEyeContourAnalyzer(),
    eyeOcclusionCheck: const CheckNoEyeOcclusion(),
    glassesAnalyzer: glassesAnalyzer ?? FakeGlassesClassifierAnalyzer(),
  );
}

// --- Tests -----------------------------------------------------------------

void main() {
  late FakeMediaPipeFaceDetectionAnalyzer faceAnalyzer;
  late FakeHandAnalyzer handAnalyzer;
  late FakeFaceLandmarkerAnalyzer landmarkerAnalyzer;
  late ValidateCapture usecase;

  setUp(() {
    faceAnalyzer = FakeMediaPipeFaceDetectionAnalyzer();
    handAnalyzer = FakeHandAnalyzer();
    landmarkerAnalyzer = FakeFaceLandmarkerAnalyzer();
    usecase = _buildUseCase(
      faceAnalyzer: faceAnalyzer,
      handAnalyzer: handAnalyzer,
      landmarkerAnalyzer: landmarkerAnalyzer,
    );
  });

  group('golden path', () {
    test('face passes + no hand + good visibility → passed', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = Ok(const {
        FaceLandmarkType.noseBase: Confidence(0.95),
        FaceLandmarkType.mouthLeft: Confidence(0.95),
        FaceLandmarkType.mouthRight: Confidence(0.95),
        FaceLandmarkType.mouthBottom: Confidence(0.95),
      });

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.passed, isTrue);
      expect(result.failure, isNull);
    });

    test('face passes + no hand + empty visibility map → passed', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = const Ok({});

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.passed, isTrue);
    });
  });

  group('sunglasses classifier gate', () {
    test('sunglasses detected → eyeOccluded + glassesEvidence populated',
        () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = const Ok({});
      final glasses = FakeGlassesClassifierAnalyzer()
        ..nextResult = const Ok(
            GlassesEvidence(sunglassesProba: 0.91, threshold: 0.5));
      usecase = _buildUseCase(
        faceAnalyzer: faceAnalyzer,
        handAnalyzer: handAnalyzer,
        landmarkerAnalyzer: landmarkerAnalyzer,
        glassesAnalyzer: glasses,
      );

      final result = await usecase(_frame, thresholds: _defaultThresholds);

      expect(result.failure, LivenessFailure.eyeOccluded);
      expect(result.glassesEvidence?.isWearingSunglasses, isTrue);
    });

    test('classifier error → skipped, capture still passes', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = const Ok({});
      final glasses = FakeGlassesClassifierAnalyzer()
        ..nextResult = Err(AnalyzerError('model boom'));
      usecase = _buildUseCase(
        faceAnalyzer: faceAnalyzer,
        handAnalyzer: handAnalyzer,
        landmarkerAnalyzer: landmarkerAnalyzer,
        glassesAnalyzer: glasses,
      );

      final result = await usecase(_frame, thresholds: _defaultThresholds);

      expect(result.passed, isTrue);
      expect(result.glassesEvidence, isNull);
    });

    test('glassesEnabled=false → not blocked even when sunglasses present',
        () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = const Ok({});
      final glasses = FakeGlassesClassifierAnalyzer()
        ..nextResult = const Ok(
            GlassesEvidence(sunglassesProba: 0.99, threshold: 0.5));
      usecase = _buildUseCase(
        faceAnalyzer: faceAnalyzer,
        handAnalyzer: handAnalyzer,
        landmarkerAnalyzer: landmarkerAnalyzer,
        glassesAnalyzer: glasses,
      );

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
        checks: const PostCaptureChecks(
          faceEnabled: true,
          handEnabled: true,
          eyeOcclusionEnabled: false,
          glassesEnabled: false,
        ),
      );

      expect(result.passed, isTrue);
    });
  });

  group('face detection gate', () {
    test('face analyzer error → analyzerError', () async {
      faceAnalyzer.nextResult = Err(AnalyzerError('boom'));

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.failure, LivenessFailure.analyzerError);
    });

    test('no face passing threshold → noFace', () async {
      faceAnalyzer.nextResult = const Ok([
        FaceDetection(
          boundingBox: Rect2D.fromLTWH(0, 0, 100, 100),
          score: Confidence(0.40),
        ),
      ]);

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.failure, LivenessFailure.noFace);
    });

    test('face score below custom threshold → noFace, same score above custom threshold → passed', () async {
      const lowFace = FaceDetection(
        boundingBox: Rect2D.fromLTWH(100, 100, 200, 250),
        score: Confidence(0.92),
      );
      faceAnalyzer.nextResult = const Ok([lowFace]);
      landmarkerAnalyzer.nextResult = const Ok({});

      final failResult = await usecase(
        _frame,
        thresholds: _defaultThresholds.copyWith(faceScore: 0.95),
      );
      expect(failResult.failure, LivenessFailure.noFace);

      final passResult = await usecase(
        _frame,
        thresholds: _defaultThresholds.copyWith(faceScore: 0.90),
      );
      expect(passResult.passed, isTrue);
    });
  });

  group('hand gate', () {
    test('hand analyzer error → analyzerError', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      handAnalyzer.nextResult = Err(AnalyzerError('hand boom'));

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.failure, LivenessFailure.analyzerError);
    });
  });

  group('check toggles', () {
    test('faceEnabled=false → empty face result passes', () async {
      faceAnalyzer.nextResult = const Ok([]); // would be noFace if enabled

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
        checks: const PostCaptureChecks(
          faceEnabled: false,
          handEnabled: true,
          eyeOcclusionEnabled: false,
          glassesEnabled: false,
        ),
      );

      expect(result.passed, isTrue);
      expect(result.faceScore, isNull);
    });

    test('handEnabled=false → hand analyzer error is ignored', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = const Ok({});
      handAnalyzer.nextResult = Err(AnalyzerError('hand boom'));

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
        checks: const PostCaptureChecks(
          faceEnabled: true,
          handEnabled: false,
          eyeOcclusionEnabled: false,
          glassesEnabled: false,
        ),
      );

      expect(result.passed, isTrue);
    });

    test('both disabled → passed regardless of analyzer errors', () async {
      faceAnalyzer.nextResult = Err(AnalyzerError('face boom'));
      handAnalyzer.nextResult = Err(AnalyzerError('hand boom'));

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
        checks: const PostCaptureChecks(
          faceEnabled: false,
          handEnabled: false,
          eyeOcclusionEnabled: false,
          glassesEnabled: false,
        ),
      );

      expect(result.passed, isTrue);
      expect(result.faceScore, isNull);
    });
  });

  // TODO: re-enable when FaceLandmarker check is restored in ValidateCapture.
  group('face landmarker occlusion gate', skip: 'FaceLandmarker temporarily disabled', () {
    test('mouth landmark visibility below threshold → objectOccluding', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = Ok(const {
        FaceLandmarkType.mouthLeft: Confidence(0.4),
      });

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.failure, LivenessFailure.objectOccluding);
    });

    test('nose visibility below threshold → objectOccluding', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = Ok(const {
        FaceLandmarkType.noseBase: Confidence(0.2),
        FaceLandmarkType.mouthLeft: Confidence(0.95),
        FaceLandmarkType.mouthRight: Confidence(0.95),
        FaceLandmarkType.mouthBottom: Confidence(0.95),
      });

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.failure, LivenessFailure.objectOccluding);
    });

    test('landmarker error → analyzerError', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = Err(AnalyzerError('model crash'));

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.failure, LivenessFailure.analyzerError);
    });

    test('landmark not found (empty visibility) → passed', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = const Ok({});

      final result = await usecase(
        _frame,
        thresholds: _defaultThresholds,
      );

      expect(result.passed, isTrue);
    });

    test('visibility 0.65 fails at default threshold (0.70), passes with lowered threshold (0.60)', () async {
      faceAnalyzer.nextResult = const Ok([_goodFace]);
      landmarkerAnalyzer.nextResult = Ok(const {
        FaceLandmarkType.noseBase: Confidence(0.65),
      });

      final failResult = await usecase(
        _frame,
        thresholds: _defaultThresholds, // landmarkVisibility = 0.70
      );
      expect(failResult.failure, LivenessFailure.objectOccluding);

      final passResult = await usecase(
        _frame,
        thresholds: _defaultThresholds.copyWith(landmarkVisibility: 0.60),
      );
      expect(passResult.passed, isTrue);
    });
  });
}

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/env.dart';
import '../../application/batch/pre_capture_score_thresholds.dart';
import '../../application/batch/score_frame_analyzer.dart';
import '../../application/flow/liveness_flow_event.dart';
import '../../application/flow/liveness_flow_machine.dart';
import '../../application/flow/liveness_flow_state.dart';
import '../../application/usecases/check_no_eye_occlusion.dart';
import '../../application/usecases/run_pipeline.dart';
import '../../application/usecases/validate_capture.dart';
import '../../domain/entities/attempt_draft.dart';
import '../../domain/repositories/eye_contour_analyzer.dart';
import '../../domain/repositories/face_analyzer.dart';
import '../../domain/repositories/glasses_classifier_analyzer.dart';
import '../../domain/repositories/hand_analyzer.dart';
import '../../domain/repositories/liveness_result_repository.dart';
import '../../domain/repositories/object_analyzer.dart';
import '../../infrastructure/camera/camera_frame_source.dart';
import '../../infrastructure/camera/input_image_converter.dart';
import '../../infrastructure/image/frame_jpeg_encoder.dart';
import '../../infrastructure/mediapipe/mediapipe_face_detection_analyzer.dart';
import '../../infrastructure/mediapipe/mediapipe_face_landmarker_analyzer.dart';
import '../../infrastructure/mediapipe/mediapipe_glasses_classifier_analyzer.dart';
import '../../infrastructure/mediapipe/mediapipe_hand_analyzer.dart';
import '../../infrastructure/mediapipe/mediapipe_object_analyzer.dart';
import '../../infrastructure/mlkit/mlkit_eye_contour_analyzer.dart';
import '../../infrastructure/mlkit/mlkit_face_analyzer.dart';
import '../../infrastructure/platform_channels/mediapipe_channel.dart';
import '../../infrastructure/supabase/supabase_liveness_result_repository.dart';
import '../coordinators/batch_capture_coordinator.dart';
import 'post_capture_thresholds_provider.dart';

/// Camera source (singleton per session).
final cameraSourceProvider = Provider<CameraFrameSource>((ref) {
  final source = CameraFrameSource();
  ref.onDispose(source.dispose);
  return source;
});

final inputImageConverterProvider = Provider<InputImageConverter>((ref) {
  return const InputImageConverter();
});

/// MediaPipe channel — shared by hand + object analyzers.
final mediaPipeChannelProvider = Provider<MediaPipeChannel>((ref) {
  final channel = MediaPipeChannel();
  ref.onDispose(channel.dispose);
  return channel;
});

final faceAnalyzerProvider = Provider<FaceAnalyzer>((ref) {
  final analyzer = MlKitFaceAnalyzer();
  ref.onDispose(analyzer.dispose);
  return analyzer;
});

final handAnalyzerProvider = Provider<HandAnalyzer>((ref) {
  final analyzer = MediaPipeHandAnalyzer(ref.read(mediaPipeChannelProvider));
  ref.onDispose(analyzer.dispose);
  return analyzer;
});

final objectAnalyzerProvider = Provider<ObjectAnalyzer>((ref) {
  final analyzer = MediaPipeObjectAnalyzer(ref.read(mediaPipeChannelProvider));
  ref.onDispose(analyzer.dispose);
  return analyzer;
});

final faceDetectionAnalyzerProvider = Provider<MediaPipeFaceDetectionAnalyzer>((ref) {
  return MediaPipeFaceDetectionAnalyzer(ref.read(mediaPipeChannelProvider));
});

final faceLandmarkerAnalyzerProvider = Provider<MediaPipeFaceLandmarkerAnalyzer>((ref) {
  return MediaPipeFaceLandmarkerAnalyzer(ref.read(mediaPipeChannelProvider));
});

final eyeContourAnalyzerProvider = Provider<EyeContourAnalyzer>((ref) {
  final analyzer = MlKitEyeContourAnalyzer();
  ref.onDispose(analyzer.dispose);
  return analyzer;
});

final glassesClassifierAnalyzerProvider =
    Provider<GlassesClassifierAnalyzer>((ref) {
  // Runs through MediaPipe's own ImageClassifier (shared embedded TFLite), so
  // it links cleanly alongside the hand/face tasks — unlike tflite_flutter,
  // which collided with MediaPipe's TFLite on iOS (duplicate symbols).
  // Requires the MediaPipe-shaped model (NHWC + metadata); see
  // tools/glasses_export/README.md.
  // Threshold is user-tunable on the home screen — watch it so the analyzer
  // (and the GlassesEvidence it stamps) reflects the live value.
  final threshold = ref.watch(
    postCaptureThresholdsProvider.select((t) => t.glassesThreshold),
  );
  final analyzer = MediaPipeGlassesClassifierAnalyzer(
    ref.read(mediaPipeChannelProvider),
    threshold: threshold,
  );
  ref.onDispose(analyzer.dispose);
  return analyzer;
});

final validateCaptureProvider = Provider<ValidateCapture>((ref) {
  return ValidateCapture(
    faceAnalyzer: ref.read(faceDetectionAnalyzerProvider),
    handAnalyzer: ref.read(handAnalyzerProvider),
    faceLandmarkerAnalyzer: ref.read(faceLandmarkerAnalyzerProvider),
    eyeContourAnalyzer: ref.read(eyeContourAnalyzerProvider),
    eyeOcclusionCheck: const CheckNoEyeOcclusion(),
    // watch: rebuild when the glasses threshold changes so the analyzer carries
    // the live value.
    glassesAnalyzer: ref.watch(glassesClassifierAnalyzerProvider),
  );
});

final pipelineProvider = Provider<RunPipeline>((ref) {
  return RunPipeline();
});

// ---------------------------------------------------------------------------
// Pre-capture 5-frame batch — replaces post-capture validation at runtime.
// ---------------------------------------------------------------------------

final preCaptureScoreThresholdsProvider =
    Provider<PreCaptureScoreThresholds>((ref) {
  return PreCaptureScoreThresholds.defaults;
});

final scoreFrameAnalyzerProvider = Provider<ScoreFrameAnalyzer>((ref) {
  return ScoreFrameAnalyzer(
    channel: ref.read(mediaPipeChannelProvider),
    face: ref.read(faceDetectionAnalyzerProvider),
    hand: ref.read(handAnalyzerProvider),
    // watch: rebuild when the glasses threshold changes so the per-frame
    // GlassesEvidence (and result-screen emphasis) uses the live value.
    glasses: ref.watch(glassesClassifierAnalyzerProvider),
  );
});

final frameJpegEncoderProvider = Provider<FrameJpegEncoder>((ref) {
  return FrameJpegEncoder(ref.read(mediaPipeChannelProvider));
});

final batchCaptureCoordinatorProvider =
    Provider<BatchCaptureCoordinator>((ref) {
  final encoder = ref.read(frameJpegEncoderProvider);
  return BatchCaptureCoordinator(
    encoder: encoder.encodeToTempFile,
  );
});

final flowMachineProvider = Provider<LivenessFlowMachine>((ref) {
  return const LivenessFlowMachine();
});

/// Flow state controller — driven by [LivenessFlowEvent]s.
class FlowController extends Notifier<LivenessFlowState> {
  @override
  LivenessFlowState build() => const FlowIdle();

  void dispatch(LivenessFlowEvent event) {
    final machine = ref.read(flowMachineProvider);
    final previous = state;
    final next = machine.reduce(previous, event);
    if (next == previous) return;
    state = next;
    if (next is FlowInitializing && previous is! FlowEvaluating) {
      ref.read(pipelineProvider).resetLivenessChallenges();
    }
  }

  void reset() {
    ref.read(pipelineProvider).resetLivenessChallenges();
    state = const FlowIdle();
  }
}

final flowControllerProvider =
    NotifierProvider<FlowController, LivenessFlowState>(FlowController.new);

// ---------------------------------------------------------------------------
// Attempt draft — tracks the in-flight attempt id and start time.
// ---------------------------------------------------------------------------

class AttemptDraftController extends Notifier<AttemptDraft?> {
  @override
  AttemptDraft? build() => null;

  void startNew() {
    state = AttemptDraft(
      id: const Uuid().v4(),
      startedAt: DateTime.now().toUtc(),
    );
  }

  void clear() => state = null;
}

final attemptDraftProvider =
    NotifierProvider<AttemptDraftController, AttemptDraft?>(
        AttemptDraftController.new);

// ---------------------------------------------------------------------------
// Supabase + persistence providers
// ---------------------------------------------------------------------------

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!Env.isConfigured) return null;
  return Supabase.instance.client;
});

final livenessResultRepositoryProvider =
    Provider<LivenessResultRepository?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return SupabaseLivenessResultRepository(client);
});

final deviceContextProvider = FutureProvider<DeviceContext>((ref) async {
  final info = await PackageInfo.fromPlatform();
  final appVersion = '${info.version}+${info.buildNumber}';
  String platform;
  String? deviceModel;
  if (Platform.isAndroid) {
    final di = await DeviceInfoPlugin().androidInfo;
    platform = 'android';
    deviceModel = di.model;
  } else if (Platform.isIOS) {
    final di = await DeviceInfoPlugin().iosInfo;
    platform = 'ios';
    deviceModel = di.utsname.machine;
  } else {
    platform = Platform.operatingSystem;
  }
  return DeviceContext(
    platform: platform,
    appVersion: appVersion,
    deviceModel: deviceModel,
  );
});

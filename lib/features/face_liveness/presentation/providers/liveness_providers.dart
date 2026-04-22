import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/env.dart';
import '../../application/flow/liveness_flow_event.dart';
import '../../application/flow/liveness_flow_machine.dart';
import '../../application/flow/liveness_flow_state.dart';
import '../../application/usecases/run_pipeline.dart';
import '../../application/usecases/validate_capture.dart';
import '../../domain/entities/attempt_draft.dart';
import '../../domain/repositories/face_analyzer.dart';
import '../../domain/repositories/hand_analyzer.dart';
import '../../domain/repositories/liveness_result_repository.dart';
import '../../domain/repositories/object_analyzer.dart';
import '../../infrastructure/camera/camera_frame_source.dart';
import '../../infrastructure/camera/input_image_converter.dart';
import '../../infrastructure/mediapipe/mediapipe_face_detection_analyzer.dart';
import '../../infrastructure/mediapipe/mediapipe_hand_analyzer.dart';
import '../../infrastructure/mediapipe/mediapipe_object_analyzer.dart';
import '../../infrastructure/mlkit/mlkit_face_analyzer.dart';
import '../../infrastructure/platform_channels/mediapipe_channel.dart';
import '../../infrastructure/supabase/supabase_liveness_result_repository.dart';

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

final validateCaptureProvider = Provider<ValidateCapture>((ref) {
  return ValidateCapture(
    faceAnalyzer: ref.read(faceDetectionAnalyzerProvider),
    handAnalyzer: ref.read(handAnalyzerProvider),
  );
});

final pipelineProvider = Provider<RunPipeline>((ref) {
  return RunPipeline();
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
    final next = machine.reduce(state, event);
    if (next != state) {
      state = next;
      if (next is FlowInitializing && state is! FlowEvaluating) {
        ref.read(pipelineProvider).resetLivenessChallenges();
      }
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

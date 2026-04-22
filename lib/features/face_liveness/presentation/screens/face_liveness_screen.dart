import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_constants.dart';
import '../../../../core/app_strings.dart';
import '../../application/flow/liveness_flow_event.dart';
import '../../application/flow/liveness_flow_state.dart';
import '../../application/usecases/run_pipeline.dart';
import '../../domain/entities/face_snapshot.dart';
import '../../domain/entities/frame_data.dart';
import '../../domain/entities/liveness_gate.dart';
import '../../domain/failures/liveness_failure.dart';
import '../../domain/value_objects/rect2d.dart';
import '../../infrastructure/camera/camera_frame_source.dart';
import '../../infrastructure/image/jpeg_frame_decoder.dart';
import '../../infrastructure/mlkit/mlkit_face_analyzer.dart';
import '../providers/liveness_providers.dart';
import '../widgets/face_oval_overlay.dart';
import '../widgets/instruction_banner.dart';
import '../widgets/step_indicator.dart';
import 'result_screen.dart';

class FaceLivenessScreen extends ConsumerStatefulWidget {
  const FaceLivenessScreen({super.key});

  @override
  ConsumerState<FaceLivenessScreen> createState() => _FaceLivenessScreenState();
}

class _FaceLivenessScreenState extends ConsumerState<FaceLivenessScreen>
    with WidgetsBindingObserver {
  bool _processing = false;
  bool _initialized = false;
  Timer? _gateTimeout;
  late final CameraFrameSource _cameraSource;

  @override
  void initState() {
    super.initState();
    _cameraSource = ref.read(cameraSourceProvider);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _gateTimeout?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Stop stream before disposing controller (spec §Camera lifecycle).
    // Uses cached source — ref is unavailable during dispose.
    unawaited(_cameraSource.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_cameraSource.stopStream());
    } else if (state == AppLifecycleState.resumed) {
      // Re-bootstrap if we lost the camera.
      if (_initialized &&
          _cameraSource.controller != null &&
          !_cameraSource.isStreaming) {
        unawaited(_startStream());
      }
    }
  }

  Future<void> _bootstrap() async {
    final controller = ref.read(flowControllerProvider.notifier);
    controller.dispatch(const StartRequested());
    final camera = ref.read(cameraSourceProvider);
    try {
      // Initialize camera + MediaPipe (face detector + hand landmarker loaded).
      await camera.initialize();
      await ref.read(handAnalyzerProvider).initialize();
      if (!mounted) return;
      setState(() => _initialized = true);
      await _startStream();
      controller.dispatch(const InitializationCompleted());
      _armGateTimeout();
    } catch (e) {
      controller.dispatch(const InitializationFailed(LivenessFailure.cameraError));
    }
  }

  Future<void> _startStream() async {
    final camera = ref.read(cameraSourceProvider);
    await camera.startStream(_onCameraImage);
  }

  void _onCameraImage(CameraImage image) {
    if (_processing) return; // drop frames while one is in flight
    _processing = true;
    unawaited(_process(image).whenComplete(() => _processing = false));
  }

  Future<void> _process(CameraImage image) async {
    final flow = ref.read(flowControllerProvider);
    if (flow is! FlowEvaluating) return; // only run pipeline while evaluating

    final camera = ref.read(cameraSourceProvider);
    final converter = ref.read(inputImageConverterProvider);
    final cameraDesc = camera.currentCamera;
    if (cameraDesc == null) return;

    final frame = converter.toFrameData(image, cameraDesc.sensorOrientation);
    final inputImage = converter.toMlKitInputImage(image, cameraDesc, 0);
    if (inputImage == null) return;

    final faceAnalyzer = ref.read(faceAnalyzerProvider);
    if (faceAnalyzer is MlKitFaceAnalyzer) {
      faceAnalyzer.setPendingInputImage(inputImage);
    }

    FaceSnapshot? face;

    final faceResult = await faceAnalyzer.analyze(frame);
    faceResult.fold((value) => face = value, (_) {});

    if (!mounted) return;

    final ovalGuide = _ovalGuideInFrameSpace(image.width, image.height);
    final input = PipelineFrameInput(
      face: face,
      hands: const [],
      objects: const [],
      ovalGuide: ovalGuide,
      frame: frame.metadata,
    );
    final outcome = ref.read(pipelineProvider).evaluate(flow.gate, input);

    if (!mounted) return;
    final controller = ref.read(flowControllerProvider.notifier);
    controller.dispatch(FrameAnalyzed(outcome));

    // On gate change, re-arm timeout.
    final nextFlow = ref.read(flowControllerProvider);
    if (nextFlow is FlowEvaluating && nextFlow.gate != flow.gate) {
      _armGateTimeout();
    }
    if (nextFlow is FlowCapturing) {
      _gateTimeout?.cancel();
      unawaited(_capture());
    }
  }

  /// Build a Rect2D in the camera frame's coordinate space that corresponds
  /// to the on-screen oval. Since the preview aspect differs from the oval,
  /// we approximate using the oval occupying 70% of frame width and centered.
  Rect2D _ovalGuideInFrameSpace(int frameWidth, int frameHeight) {
    final w = frameWidth * 0.7;
    final h = frameHeight * 0.55;
    final left = (frameWidth - w) / 2;
    final top = (frameHeight - h) / 2 - frameHeight * 0.05;
    return Rect2D.fromLTWH(left, top, w, h);
  }

  void _armGateTimeout() {
    _gateTimeout?.cancel();
    _gateTimeout = Timer(AppConstants.gateTimeout, () {
      if (!mounted) return;
      ref.read(flowControllerProvider.notifier).dispatch(const TimeoutElapsed());
    });
  }

  Future<void> _capture() async {
    final camera = ref.read(cameraSourceProvider);
    final path = await camera.takePicture();
    if (!mounted) return;
    final controller = ref.read(flowControllerProvider.notifier);
    if (path == null) {
      controller.dispatch(const CaptureFailed(LivenessFailure.cameraError));
      return;
    }

    // Silent post-capture validation: face score ≥ 95% AND zero hands in frame.
    final FrameData frame;
    try {
      frame = await JpegFrameDecoder.decode(path);
    } catch (_) {
      controller.dispatch(const CaptureFailed(LivenessFailure.cameraError));
      return;
    }
    if (!mounted) return;

    final result = await ref.read(validateCaptureProvider).call(frame);
    if (!mounted) return;

    if (result.passed) {
      controller.dispatch(CaptureComplete(path, faceScore: result.faceScore!));
    } else {
      controller.dispatch(CaptureFailed(result.failure!));
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ResultScreen(photoPath: path, validation: result),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(flowControllerProvider);
    final camera = ref.watch(cameraSourceProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_initialized && camera.controller != null)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: camera.controller!.value.previewSize?.height ?? 1,
                    height: camera.controller!.value.previewSize?.width ?? 1,
                    child: CameraPreview(camera.controller!),
                  ),
                ),
              )
            else
              const Center(
                child: Text(
                  AppStrings.preparing,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            Positioned.fill(
              child: FaceOvalOverlay(status: _ovalStatus(flow)),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: InstructionBanner(
                text: _instructionFor(flow),
                status: _ovalStatus(flow),
              ),
            ),
            Positioned(
              bottom: 32,
              left: 24,
              right: 24,
              child: StepIndicator(currentGate: _gateOf(flow)),
            ),
            if (flow is FlowFailed)
              Positioned(
                bottom: 100,
                left: 24,
                right: 24,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: () {
                        ref.read(flowControllerProvider.notifier).dispatch(const UserRetry());
                        _gateTimeout?.cancel();
                        Future.microtask(_bootstrap);
                      },
                      child: const Text(AppStrings.retry),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  LivenessGate? _gateOf(LivenessFlowState s) =>
      s is FlowEvaluating ? s.gate : null;

  OvalStatus _ovalStatus(LivenessFlowState s) => switch (s) {
        FlowIdle _ => OvalStatus.neutral,
        FlowInitializing _ => OvalStatus.working,
        FlowEvaluating e => e.lastFailure != null ? OvalStatus.failure : OvalStatus.working,
        FlowCapturing _ => OvalStatus.success,
        FlowDone _ => OvalStatus.success,
        FlowFailed _ => OvalStatus.failure,
      };

  String _instructionFor(LivenessFlowState s) {
    return switch (s) {
      FlowIdle _ => AppStrings.preparing,
      FlowInitializing _ => AppStrings.preparing,
      FlowEvaluating e when e.lastFailure != null => e.lastFailure!.thaiMessage,
      FlowEvaluating e => _defaultPromptFor(e.gate),
      FlowCapturing _ => AppStrings.verifying,
      FlowDone _ => AppStrings.verificationSuccess,
      FlowFailed f => f.reason.thaiMessage,
    };
  }

  String _defaultPromptFor(LivenessGate gate) => switch (gate) {
        LivenessGate.faceQuality => AppStrings.frameYourFace,
        LivenessGate.livenessSmile => AppStrings.pleaseSmile,
        LivenessGate.livenessBlink => AppStrings.pleaseBlink,
      };
}

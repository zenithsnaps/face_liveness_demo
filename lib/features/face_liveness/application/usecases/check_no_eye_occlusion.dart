import '../../domain/entities/eye_occlusion_evidence.dart';
import '../../domain/entities/eye_regions.dart';
import '../../domain/entities/frame_data.dart';
import '../utils/eye_occlusion_thresholds.dart';
import '../utils/eye_occlusion_util.dart';

/// Post-capture check: detect sunglasses or other eye-covering objects via
/// pixel-level analysis of the eye contour regions.
///
/// Delegates to [EyeOcclusionUtil.detect]. Use that directly when you don't
/// need dependency injection.
class CheckNoEyeOcclusion {
  final EyeOcclusionThresholds thresholds;

  const CheckNoEyeOcclusion({
    this.thresholds = EyeOcclusionThresholds.defaults,
  });

  EyeOcclusionEvidence call({
    required FrameData frame,
    required EyeRegions regions,
  }) =>
      EyeOcclusionUtil.detect(
        frame: frame,
        regions: regions,
        thresholds: thresholds,
      );
}

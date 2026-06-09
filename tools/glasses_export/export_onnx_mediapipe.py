"""Export glasses-detector 'sunglasses' head for the MediaPipe Tasks
ImageClassifier runtime (so the model runs on MediaPipe's OWN embedded TFLite —
no second TFLite framework, no iOS duplicate-symbol clash with
MediaPipeTasksCommon, and it coexists with MediaPipe hand detection).

⚠️  THIS SCRIPT EXPORTS THE *BASE* glasses-detector WEIGHTS — NOT the model we
ship. Production uses the Thai-funnel FINE-TUNED weights (FPR 1.9%→0.6%, see
finetune.py / README). To build the MediaPipe-shaped *fine-tuned* model, run
`strip_preproc_for_mediapipe.py` on `glasses_sunglasses_ft.onnx` instead — it
externalizes the same preprocessing from the already-fine-tuned graph. Use this
script only for parity/debugging against the base model.

Differs from the native NCHW path (`export_onnx.py`) in two ways:

1. Preprocessing is NOT baked into the graph. `/255` + ImageNet normalize move
   into TFLite NormalizationOptions metadata (see `add_mediapipe_metadata.py`),
   which MediaPipe applies for us. We keep ONLY the final sigmoid so the single
   output is P(sunglasses) directly.
2. The graph stays NCHW here; `onnx2tf` (WITHOUT `-kat`) transposes it to the
   NHWC layout MediaPipe requires. Stripping the input preprocessing subgraph
   also sidesteps the onnx2tf pickle bug that forced `-kat image` (NCHW) before.

Final tflite contract (after onnx2tf + add_mediapipe_metadata.py):
  input  : float32 NHWC (1, 256, 256, 3), RGB. MediaPipe normalizes with
           mean = 255*ImageNet, std = 255*ImageNet (set in metadata).
  output : float32 (1, 1) = P(sunglasses); 1-label map ["sunglasses"].
"""
import warnings; warnings.filterwarnings("ignore")
import torch, torch.nn as nn
from glasses_detector import GlassesClassifier

clf = GlassesClassifier(kind="sunglasses", size="small")
core = clf.model.eval().cpu()


class GlassesSunglassesCore(nn.Module):
    """Core backbone + sigmoid only.

    Input is ALREADY ImageNet-normalized: MediaPipe does `/255` and
    `(x - mean) / std` via NormalizationOptions metadata before the model sees
    the tensor, so the graph must NOT repeat it.
    """

    def __init__(self, core):
        super().__init__()
        self.core = core

    def forward(self, x):                  # x: (N,3,256,256) normalized domain
        return torch.sigmoid(self.core(x))  # (N,1) probability


model = GlassesSunglassesCore(core).eval()

# Dummy lives in the normalized domain now; values don't change graph structure.
dummy = torch.zeros(1, 3, 256, 256)
with torch.no_grad():
    print("self-test output (zeros, normalized domain):", float(model(dummy)))

torch.onnx.export(
    model, dummy, "glasses_sunglasses_mp.onnx",
    input_names=["image"], output_names=["sunglasses_proba"],
    opset_version=17, dynamic_axes=None,   # fixed batch=1 for mobile
)
print("exported glasses_sunglasses_mp.onnx "
      "(preprocessing externalized to metadata; sigmoid kept)")

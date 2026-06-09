"""Export glasses-detector 'sunglasses' (TinyBinaryClassifier) to ONNX with
preprocessing (/255 + ImageNet normalize) and sigmoid baked in.

Resulting contract:
  input  : float32 (1, 3, 256, 256), RGB pixel values in [0, 255]
  output : float32 (1, 1), P(sunglasses) in [0, 1]
"""
import warnings; warnings.filterwarnings("ignore")
import torch, torch.nn as nn
from glasses_detector import GlassesClassifier

clf = GlassesClassifier(kind="sunglasses", size="small")
core = clf.model.eval().cpu()

class GlassesSunglassesModel(nn.Module):
    def __init__(self, core):
        super().__init__()
        self.core = core
        # ImageNet stats, shaped for broadcasting over (N,3,H,W)
        self.register_buffer("mean", torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1))
        self.register_buffer("std",  torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1))

    def forward(self, x):                 # x: (N,3,256,256) RGB in [0,255]
        x = x / 255.0
        x = (x - self.mean) / self.std
        logit = self.core(x)              # (N,1) raw score
        return torch.sigmoid(logit)       # (N,1) probability

model = GlassesSunglassesModel(core).eval()

dummy = torch.zeros(1, 3, 256, 256)       # RGB 0..255
with torch.no_grad():
    print("self-test output (zeros):", float(model(dummy)))

torch.onnx.export(
    model, dummy, "glasses_sunglasses.onnx",
    input_names=["image"], output_names=["sunglasses_proba"],
    opset_version=17, dynamic_axes=None,  # fixed batch=1 for mobile
)
print("exported glasses_sunglasses.onnx")

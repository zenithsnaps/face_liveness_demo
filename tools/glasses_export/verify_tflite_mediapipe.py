"""Parity check for the MediaPipe-variant tflite (NHWC, preprocessing BAKED).

The production MediaPipe model bakes `/255` + ImageNet norm + sigmoid into the
graph (MediaPipe can't do per-channel norm in metadata), so the input is raw
[0,255] RGB — feed it as-is, no manual normalization. Expect frame5 ~ 0.9295
(fine-tuned). For a true MediaPipe-runtime check use the ImageClassifier path
in the README instead; this is the bare-interpreter numeric parity.
"""
import warnings; warnings.filterwarnings("ignore")
import sys
import numpy as np
from PIL import Image
from glasses_detector import GlassesClassifier
try:
    from ai_edge_litert.interpreter import Interpreter
except Exception:
    from tensorflow.lite import Interpreter

IMAGES = [
    ("1.jpg", "reflective sunglasses"), ("2.jpg", "matte black"),
    ("3.jpg", "green translucent"), ("frame5.jpg", "frame5 selfie"),
    ("noglasses.jpg", "NO glasses"),
]

model_path = sys.argv[1] if len(sys.argv) > 1 else "glasses_sunglasses_mp.tflite"
clf = GlassesClassifier(kind="sunglasses", size="small")

interp = Interpreter(model_path=model_path)
interp.allocate_tensors()
inp = interp.get_input_details()[0]
out = interp.get_output_details()[0]
print("TFLite input :", inp["shape"], inp["dtype"].__name__)  # expect (1,256,256,3)
print("TFLite output:", out["shape"], out["dtype"].__name__)
assert inp["shape"][-1] == 3, "expected NHWC (1,256,256,3) for the MediaPipe model"


def preprocess(path):
    img = Image.open(path).convert("RGB").resize((256, 256))
    return np.asarray(img, dtype=np.float32)[None]       # NHWC, raw [0,255]


print(f"\n{'image':24} | {'PyTorch':>8} | {'TFLite':>8} | {'diff':>8}")
print("-"*24 + "-+-" + "-+-".join(["-"*8]*3))
maxdiff = 0.0
for path, desc in IMAGES:
    pt = float(clf(path, format="proba"))
    interp.set_tensor(inp["index"], preprocess(path))
    interp.invoke()
    tf_out = float(interp.get_tensor(out["index"]).reshape(-1)[0])
    d = abs(pt - tf_out); maxdiff = max(maxdiff, d)
    print(f"{desc:24} | {pt:8.4f} | {tf_out:8.4f} | {d:8.5f}")
print(f"\nmax abs diff = {maxdiff:.5f}  -> {'MATCH (ok)' if maxdiff < 0.02 else 'MISMATCH'}")

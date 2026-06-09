import warnings; warnings.filterwarnings("ignore")
import numpy as np, onnxruntime as ort
from PIL import Image
from glasses_detector import GlassesClassifier

IMAGES = [
    ("1.jpg", "reflective sunglasses"),
    ("2.jpg", "matte black"),
    ("3.jpg", "green translucent"),
    ("frame5.jpg", "frame5 selfie"),
    ("noglasses.jpg", "NO glasses"),
]

clf = GlassesClassifier(kind="sunglasses", size="small")  # PyTorch reference (full pipeline)
sess = ort.InferenceSession("glasses_sunglasses.onnx", providers=["CPUExecutionProvider"])

def preprocess(path):
    img = Image.open(path).convert("RGB").resize((256, 256))  # match package: PIL resize
    arr = np.asarray(img, dtype=np.float32)        # (256,256,3) RGB 0..255
    arr = np.transpose(arr, (2, 0, 1))[None]       # (1,3,256,256)
    return arr

print(f"{'image':24} | {'PyTorch':>8} | {'ONNX':>8} | {'diff':>8}")
print("-"*24 + "-+-" + "-+-".join(["-"*8]*3))
maxdiff = 0.0
for path, desc in IMAGES:
    pt = float(clf(path, format="proba"))
    onnx_out = sess.run(None, {"image": preprocess(path)})[0]
    on = float(onnx_out.reshape(-1)[0])
    d = abs(pt - on); maxdiff = max(maxdiff, d)
    print(f"{desc:24} | {pt:8.4f} | {on:8.4f} | {d:8.5f}")
print(f"\nmax abs diff = {maxdiff:.5f}  -> {'MATCH (ok)' if maxdiff < 0.02 else 'MISMATCH (check preprocessing)'}")

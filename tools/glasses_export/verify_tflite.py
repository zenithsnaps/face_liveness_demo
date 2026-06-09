import warnings; warnings.filterwarnings("ignore")
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
clf = GlassesClassifier(kind="sunglasses", size="small")

interp = Interpreter(model_path="tflite_out/glasses_sunglasses_float32.tflite")
interp.allocate_tensors()
inp = interp.get_input_details()[0]
out = interp.get_output_details()[0]
print("TFLite input :", inp["shape"], inp["dtype"].__name__)
print("TFLite output:", out["shape"], out["dtype"].__name__)
nhwc = (inp["shape"][-1] == 3)  # (1,256,256,3) NHWC vs (1,3,256,256) NCHW
print("layout:", "NHWC" if nhwc else "NCHW")

def preprocess(path):
    img = Image.open(path).convert("RGB").resize((256, 256))
    arr = np.asarray(img, dtype=np.float32)          # (256,256,3) RGB 0..255
    if not nhwc:
        arr = np.transpose(arr, (2, 0, 1))
    return arr[None]

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

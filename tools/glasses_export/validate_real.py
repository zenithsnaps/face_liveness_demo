"""Validate the SHIPPED tflite model on the user's real frames, replicating
the Dart analyzer preprocessing (face crop expanded 0.6 -> 256 NCHW 0..255)."""
import warnings; warnings.filterwarnings("ignore")
import numpy as np, cv2
from PIL import Image
try:
    from ai_edge_litert.interpreter import Interpreter
except Exception:
    from tensorflow.lite import Interpreter

DOCS = "/Users/thaworn-li/P-Projects/liveness/face_liveness_demo/docs"
MODEL = "/Users/thaworn-li/P-Projects/liveness/face_liveness_demo/assets/models/glasses_sunglasses.tflite"
IMAGES = [
    ("31f04398-d807-4a43-ba67-709c371e9d31.jpeg", "matte black",      "sunglasses"),
    ("70e1e4a9-797c-4a7e-838a-48cfe457cae6.jpeg", "wayfarer black",   "sunglasses"),
    ("102ee141-b8c8-424d-ae98-4c60bff94b38.jpeg", "green translucent","sunglasses"),
    ("Gemini_Generated_Image_brjjnhbrjjnhbrjj.png","AI-generated blk", "sunglasses"),
    ("หน้าตรงไม่ใส่แว่น.jpeg",                      "no glasses",       "none"),
]
SIZE = 256
casc = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
interp = Interpreter(model_path=MODEL); interp.allocate_tensors()
inp = interp.get_input_details()[0]; out = interp.get_output_details()[0]

def run(arr_rgb_256):  # arr: (256,256,3) RGB float 0..255 -> NCHW
    x = np.transpose(arr_rgb_256, (2,0,1))[None].astype(np.float32)
    interp.set_tensor(inp["index"], x); interp.invoke()
    return float(interp.get_tensor(out["index"]).reshape(-1)[0])

def whole(path):
    img = Image.open(path).convert("RGB").resize((SIZE,SIZE))
    return run(np.asarray(img, np.float32))

def facecrop(path, margin=0.6):
    bgr = cv2.imread(path); h,w = bgr.shape[:2]
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    faces = casc.detectMultiScale(gray, 1.1, 4, minSize=(int(min(h,w)*0.15),)*2)
    if len(faces)==0: return None
    x,y,fw,fh = max(faces, key=lambda f:f[2]*f[3])
    dx,dy = int(fw*margin), int(fh*margin)
    l,t = max(0,x-dx), max(0,y-dy); r,b = min(w,x+fw+dx), min(h,y+fh+dy)
    crop = bgr[t:b, l:r]
    rgb = cv2.cvtColor(cv2.resize(crop,(SIZE,SIZE),interpolation=cv2.INTER_LINEAR), cv2.COLOR_BGR2RGB)
    return run(rgb.astype(np.float32))

print(f"{'image':20} {'truth':11} | {'whole':>7} | {'faceCrop0.6':>11} | decision@0.5")
print("-"*20+"-"*13+"-+-"+"-"*7+"-+-"+"-"*11+"-+-"+"-"*12)
ok=0; tot=0
for fn,desc,truth in IMAGES:
    p=f"{DOCS}/{fn}"
    pw=whole(p); pc=facecrop(p)
    use = pc if pc is not None else pw
    pred = "sunglasses" if use>=0.5 else "none"
    correct = (pred==truth); ok+=correct; tot+=1
    pcs = f"{pc:.3f}" if pc is not None else "no-face"
    print(f"{desc:20} {truth:11} | {pw:7.3f} | {pcs:>11} | {pred:10} {'OK' if correct else 'WRONG'}")
print(f"\naccuracy (using faceCrop, fallback whole): {ok}/{tot}")

import warnings; warnings.filterwarnings("ignore")
import json, numpy as np, cv2, collections
try:
    from ai_edge_litert.interpreter import Interpreter
except Exception:
    from tensorflow.lite import Interpreter

MODEL="/Users/thaworn-li/P-Projects/liveness/face_liveness_demo/assets/models/glasses_sunglasses.tflite"
THRESH=0.5; S=256; MARGIN=0.6
sample=json.load(open("sample.json"))
casc=cv2.CascadeClassifier(cv2.data.haarcascades+"haarcascade_frontalface_default.xml")
it=Interpreter(model_path=MODEL); it.allocate_tensors()
ind=it.get_input_details()[0]; outd=it.get_output_details()[0]

def proba_rgb(rgb):
    x=np.transpose(rgb,(2,0,1))[None].astype(np.float32)
    it.set_tensor(ind["index"],x); it.invoke()
    return float(it.get_tensor(outd["index"]).reshape(-1)[0])

def infer(path):
    bgr=cv2.imread(path)
    if bgr is None: return None
    h,w=bgr.shape[:2]; g=cv2.cvtColor(bgr,cv2.COLOR_BGR2GRAY)
    fs=casc.detectMultiScale(g,1.1,4,minSize=(int(min(h,w)*0.15),)*2)
    if len(fs):
        x,y,fw,fh=max(fs,key=lambda f:f[2]*f[3]); dx,dy=int(fw*MARGIN),int(fh*MARGIN)
        l,t,r,b=max(0,x-dx),max(0,y-dy),min(w,x+fw+dx),min(h,y+fh+dy)
        crop=bgr[t:b,l:r]
    else:
        crop=bgr  # fallback whole frame
    rgb=cv2.cvtColor(cv2.resize(crop,(S,S),interpolation=cv2.INTER_LINEAR),cv2.COLOR_BGR2RGB)
    return proba_rgb(rgb.astype(np.float32))

# evaluate
per_label=collections.defaultdict(lambda:{"n":0,"flag":0,"probas":[]})
TP=FP=TN=FN=0; noface=0
results=[]
for i,s in enumerate(sample):
    p=infer(f"funnel/{i:03d}.jpg")
    if p is None: continue
    flag = p>=THRESH
    lab=s["label"]; pos=s["is_pos"]
    per_label[lab]["n"]+=1; per_label[lab]["flag"]+=int(flag); per_label[lab]["probas"].append(p)
    if pos and flag: TP+=1
    elif pos and not flag: FN+=1
    elif (not pos) and flag: FP+=1
    else: TN+=1
    results.append({**s,"proba":p,"flag":flag})
json.dump(results, open("funnel_results.json","w"), ensure_ascii=False)

print(f"=== per-label flag rate (threshold={THRESH}, faceCrop {MARGIN}) ===")
print(f"{'label':46} {'n':>3} {'flagged':>8} {'rate':>6} {'medianP':>8}")
for lab in sorted(per_label, key=lambda k: (k!='6. แว่นดำ', k)):
    d=per_label[lab]; rate=d['flag']/d['n'] if d['n'] else 0
    med=float(np.median(d['probas'])) if d['probas'] else 0
    print(f"{lab:46} {d['n']:>3} {d['flag']:>8} {rate:>6.1%} {med:>8.3f}")

P=TP+FN; N=TN+FP
recall=TP/P if P else 0; fpr=FP/N if N else 0
prec=TP/(TP+FP) if (TP+FP) else 0
print(f"\n=== confusion (positive = '6. แว่นดำ') ===")
print(f"  TP={TP} FN={FN}  (sunglasses, n={P})")
print(f"  FP={FP} TN={TN}  (no-sunglasses, n={N})")
print(f"  recall(sensitivity) = {recall:.1%}")
print(f"  false-positive rate = {fpr:.1%}")
print(f"  precision           = {prec:.1%}")

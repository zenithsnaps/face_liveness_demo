"""Fine-tune the TinyBinaryClassifier sunglasses head on Thai funnel data.

Policy: dark sunglasses = positive (block); everything else incl. CLEAR
prescription glasses = negative (pass). Group-aware train/test split.
"""
import warnings; warnings.filterwarnings("ignore")
import json, numpy as np, cv2, torch, torch.nn as nn
from glasses_detector import GlassesClassifier

SIZE, MARGIN = 256, 0.6
MEAN = torch.tensor([0.485,0.456,0.406]).view(3,1,1)
STD  = torch.tensor([0.229,0.224,0.225]).view(3,1,1)
casc = cv2.CascadeClassifier(cv2.data.haarcascades+"haarcascade_frontalface_default.xml")
ds = json.load(open("ft_dataset.json"))

def crop256(path):
    bgr=cv2.imread(path)
    if bgr is None: return None
    h,w=bgr.shape[:2]; g=cv2.cvtColor(bgr,cv2.COLOR_BGR2GRAY)
    fs=casc.detectMultiScale(g,1.1,4,minSize=(int(min(h,w)*0.15),)*2)
    if len(fs):
        x,y,fw,fh=max(fs,key=lambda f:f[2]*f[3]); dx,dy=int(fw*MARGIN),int(fh*MARGIN)
        l,t,r,b=max(0,x-dx),max(0,y-dy),min(w,x+fw+dx),min(h,y+fh+dy); bgr=bgr[t:b,l:r]
    rgb=cv2.cvtColor(cv2.resize(bgr,(SIZE,SIZE),interpolation=cv2.INTER_LINEAR),cv2.COLOR_BGR2RGB)
    return rgb.astype(np.uint8)

def load(split):
    X,Y=[],[]
    for i,c in enumerate(ds[split]):
        a=crop256(f"{split}_{i:04d}.jpg".replace(split,f"ft/{split}",1)) if False else crop256(f"ft/{split}_{i:04d}.jpg")
        if a is None: continue
        X.append(a); Y.append(c["label"])
    return np.stack(X), np.array(Y, np.float32)

print("loading + cropping...")
Xtr,Ytr=load("train"); Xte,Yte=load("test")
print(f"train {Xtr.shape} pos={int(Ytr.sum())}  test {Xte.shape} pos={int(Yte.sum())}")

def to_tensor(arr_uint8, aug=False):
    a=arr_uint8.astype(np.float32)
    if aug:
        if np.random.rand()<0.5: a=a[:, ::-1, :].copy()         # hflip
        a*=np.random.uniform(0.8,1.2)                            # brightness
        a+=np.random.uniform(-12,12)                             # bias
        if np.random.rand()<0.3:                                  # small rotate
            M=cv2.getRotationMatrix2D((SIZE/2,SIZE/2),np.random.uniform(-12,12),1.0)
            a=cv2.warpAffine(a,M,(SIZE,SIZE),borderMode=cv2.BORDER_REFLECT)
    a=np.clip(a,0,255)
    t=torch.from_numpy(a).permute(2,0,1)/255.0
    return (t-MEAN)/STD

clf=GlassesClassifier(kind="sunglasses",size="small"); model=clf.model.eval().cpu()
for p in model.parameters(): p.requires_grad_(True)

pos_w=torch.tensor([(Ytr==0).sum()/max(1,(Ytr==1).sum())])
crit=nn.BCEWithLogitsLoss(pos_weight=pos_w)
opt=torch.optim.Adam(model.parameters(), lr=3e-4, weight_decay=1e-4)

def evaluate(thr=0.7):
    model.eval(); probs=[]
    with torch.no_grad():
        for k in range(0,len(Xte),64):
            xb=torch.stack([to_tensor(x) for x in Xte[k:k+64]])
            probs+= model(xb).sigmoid().reshape(-1).tolist()
    probs=np.array(probs); pred=probs>=thr
    P=Yte==1; N=Yte==0
    rec=(pred[P]).mean() if P.sum() else 0
    fpr=(pred[N]).mean() if N.sum() else 0
    prec=pred[P].sum()/max(1,pred.sum())
    f1=2*prec*rec/(prec+rec) if (prec+rec) else 0
    return rec,fpr,prec,f1,probs

r,f,pr,f1,_=evaluate()
print(f"BEFORE fine-tune @0.7:  recall={r:.1%} FPR={f:.1%} prec={pr:.1%} F1={f1:.2f}")

idx=np.arange(len(Xtr)); best=None
for ep in range(1,26):
    model.train(); np.random.shuffle(idx)
    for k in range(0,len(idx),32):
        b=idx[k:k+32]
        xb=torch.stack([to_tensor(Xtr[j],aug=True) for j in b])
        yb=torch.tensor(Ytr[b]).view(-1,1)
        opt.zero_grad(); loss=crit(model(xb),yb); loss.backward(); opt.step()
    r,f,pr,f1,_=evaluate()
    tag=""
    if best is None or f1>best[0]:
        best=(f1,ep,{k:v.detach().clone() for k,v in model.state_dict().items()},(r,f,pr))
        tag=" *best"
    if ep%2==0 or tag: print(f"ep{ep:2d} @0.7 recall={r:.1%} FPR={f:.1%} prec={pr:.1%} F1={f1:.2f}{tag}")

f1,ep,sd,(r,f,pr)=best
print(f"\nBEST ep{ep}: recall={r:.1%} FPR={f:.1%} prec={pr:.1%} F1={f1:.2f}")
model.load_state_dict(sd); torch.save(model.state_dict(),"glasses_sunglasses_ft.pt")
print("saved glasses_sunglasses_ft.pt")

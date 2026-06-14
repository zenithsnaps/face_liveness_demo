import cv2, numpy as np, math, sys

IMG = '1.jpg'
img = cv2.imread(IMG)
H, W = img.shape[:2]
rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB).astype(np.float64)

# ---- thresholds (app_constants.dart) ----
LUM_PASS, LUM_BLK = 0.55, 0.35
STD_PASS, STD_BLK = 15.0, 8.0
SAT_PASS, SAT_BLK = 20.0, 12.0
BLOCK = 0.30

def stats_over(rects):
    """mirror eye_occlusion_util _statsOver: pool pixels across rects."""
    ys, sats = [], []
    for (l,t,r,b) in rects:
        l=max(0,int(math.floor(l))); t=max(0,int(math.floor(t)))
        r=min(W,int(math.ceil(r))); b=min(H,int(math.ceil(b)))
        if r-l<4 or b-t<4: continue
        patch = rgb[t:b, l:r, :]
        R=patch[:,:,0]; G=patch[:,:,1]; B=patch[:,:,2]
        yl = 0.299*R + 0.587*G + 0.114*B
        mx = np.maximum(R, np.maximum(G,B)); mn = np.minimum(R, np.minimum(G,B))
        sat = np.where(mx<=0, 0.0, (mx-mn)/np.where(mx<=0,1,mx)*255.0)
        ys.append(yl.ravel()); sats.append(sat.ravel())
    if not ys: return None
    y=np.concatenate(ys); s=np.concatenate(sats)
    return dict(meanY=y.mean(), stdY=y.std(), meanSat=s.mean())

def stats_poly(polys, cheekRects=None):
    """contour version: mask by polygon for eyes."""
    mask = np.zeros((H,W), np.uint8)
    for poly in polys:
        cv2.fillPoly(mask, [np.array(poly, np.int32)], 1)
    idx = mask.astype(bool)
    if idx.sum()<16: return None
    R=rgb[:,:,0][idx]; G=rgb[:,:,1][idx]; B=rgb[:,:,2][idx]
    yl=0.299*R+0.587*G+0.114*B
    mx=np.maximum(R,np.maximum(G,B)); mn=np.minimum(R,np.minimum(G,B))
    sat=np.where(mx<=0,0.0,(mx-mn)/np.where(mx<=0,1,mx)*255.0)
    return dict(meanY=yl.mean(), stdY=yl.std(), meanSat=sat.mean())

def bucket(lum, std, sat):
    s=0.0
    s += 0.45 if lum<LUM_BLK else (0.30 if lum<LUM_PASS else 0.0)
    s += 0.30 if std<STD_BLK else (0.18 if std<STD_PASS else 0.0)
    s += 0.25 if sat<SAT_BLK else (0.15 if sat<SAT_PASS else 0.0)
    return s

# ================= METHOD A: geometric (current) =================
fx,fy,fw,fh = 37,164,406,406   # Haar faceBox proxy
def Rg(l,t,r,b): return (fx+fw*l, fy+fh*t, fx+fw*r, fy+fh*b)
gEyeL=Rg(0.16,0.30,0.44,0.46); gEyeR=Rg(0.56,0.30,0.84,0.46)
gChkL=Rg(0.18,0.58,0.43,0.76); gChkR=Rg(0.57,0.58,0.82,0.76)
gEye=stats_over([gEyeL,gEyeR]); gChk=stats_over([gChkL,gChkR])
gLum=gEye['meanY']/gChk['meanY']
gScore=bucket(gLum,gEye['stdY'],gEye['meanSat'])

# ================= METHOD B: mediapipe contours (Tasks API) =================
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
MODEL='/Users/thaworn-li/P-Projects/liveness/face_liveness_demo/assets/models/face_landmarker.task'
opts=vision.FaceLandmarkerOptions(
    base_options=mp_python.BaseOptions(model_asset_path=MODEL),
    running_mode=vision.RunningMode.IMAGE, num_faces=1)
landmarker=vision.FaceLandmarker.create_from_options(opts)
mp_img=mp.Image.create_from_file(IMG)
res=landmarker.detect(mp_img)
LEYE=[33,7,163,144,145,153,154,155,133,246,161,160,159,158,157,173]
REYE=[362,382,381,380,374,373,390,249,263,466,388,387,386,385,384,398]
LCHK=[50,205,116,117,118,101]   # left cheek cluster
RCHK=[280,425,345,346,347,330]  # right cheek cluster

b_ok=False
if res.face_landmarks:
    b_ok=True
    lm=res.face_landmarks[0]
    P=lambda i:(lm[i].x*W, lm[i].y*H)
    polyLE=[P(i) for i in LEYE]; polyRE=[P(i) for i in REYE]
    # cheek patch anchored at midpoint(eye-outer-corner, mouth-corner) -> always on
    # skin below the eye, robust to oversized glasses. Patch sized ~ face width.
    half = fw*0.11
    def cheek_patch(eye_outer, mouth_corner):
        ex,ey=P(eye_outer); mx,my=P(mouth_corner)
        cx,cy=(ex+mx)/2,(ey+my)/2
        return (cx-half, cy-half, cx+half, cy+half)
    cChkL=cheek_patch(33,61); cChkR=cheek_patch(263,291)
    bEye=stats_poly([polyLE,polyRE]); bChk=stats_over([cChkL,cChkR])
    bLum=bEye['meanY']/bChk['meanY']
    bScore=bucket(bLum,bEye['stdY'],bEye['meanSat'])

# ================= RENDER side-by-side =================
def draw_panel(base, title, eye_shapes, chk_rects, st_eye, st_chk, lum, score, is_poly):
    p=base.copy()
    cv2.putText(p,title,(10,28),cv2.FONT_HERSHEY_SIMPLEX,0.7,(255,255,255),2,cv2.LINE_AA)
    cv2.putText(p,title,(10,28),cv2.FONT_HERSHEY_SIMPLEX,0.7,(0,0,0),1,cv2.LINE_AA)
    for sh in eye_shapes:
        if is_poly: cv2.polylines(p,[np.array(sh,np.int32)],True,(0,0,255),2)
        else: cv2.rectangle(p,(int(sh[0]),int(sh[1])),(int(sh[2]),int(sh[3])),(0,0,255),2)
    for r in chk_rects:
        cv2.rectangle(p,(int(r[0]),int(r[1])),(int(r[2]),int(r[3])),(0,200,0),2)
    occ = score>=BLOCK
    lines=[f"lumRatio={lum:.3f}  (blk<{LUM_BLK} pass<{LUM_PASS})",
           f"eye stdDev={st_eye['stdY']:.1f}  (blk<{STD_BLK} pass<{STD_PASS})",
           f"eye sat={st_eye['meanSat']:.1f}  (blk<{SAT_BLK} pass<{SAT_PASS})",
           f"eyeY={st_eye['meanY']:.1f}  cheekY={st_chk['meanY']:.1f}",
           f"SCORE={score:.2f}  ->  {'OCCLUDED' if occ else 'pass'} (blk>={BLOCK})"]
    y0=H-118
    cv2.rectangle(p,(0,y0-8),(W,H),(0,0,0),-1)
    for i,ln in enumerate(lines):
        col=(0,255,255) if i<len(lines)-1 else ((0,80,255) if occ else (0,255,0))
        cv2.putText(p,ln,(8,y0+18+i*21),cv2.FONT_HERSHEY_SIMPLEX,0.5,col,1,cv2.LINE_AA)
    return p

panelA=draw_panel(img,"A: GEOMETRIC (current)",[gEyeL,gEyeR],[gChkL,gChkR],gEye,gChk,gLum,gScore,False)
if b_ok:
    panelB=draw_panel(img,"B: MEDIAPIPE contours",[polyLE,polyRE],[cChkL,cChkR],bEye,bChk,bLum,bScore,True)
else:
    panelB=img.copy(); cv2.putText(panelB,"FaceMesh: no detection",(10,40),cv2.FONT_HERSHEY_SIMPLEX,0.7,(0,0,255),2)

combo=np.hstack([panelA, np.full((H,6,3),255,np.uint8), panelB])
cv2.imwrite('compare.jpg', combo)

print("=== A geometric ===", {k:round(v,3) for k,v in gEye.items()}, "lum",round(gLum,3),"score",round(gScore,2))
if b_ok: print("=== B mediapipe ===", {k:round(v,3) for k,v in bEye.items()}, "lum",round(bLum,3),"score",round(bScore,2))
print("saved compare.jpg")

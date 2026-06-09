import warnings, sys
warnings.filterwarnings("ignore")
from glasses_detector import GlassesClassifier

IMAGES = {
    "1.jpg (reflective sunglasses)": "1.jpg",
    "2.jpg (matte black sunglasses)": "2.jpg",
    "3.jpg (green translucent, eyes visible)": "3.jpg",
}
KINDS = ["anyglasses", "sunglasses", "eyeglasses"]

# build one classifier per kind (small = fastest, fine for a smoke test)
clfs = {}
for k in KINDS:
    try:
        clfs[k] = GlassesClassifier(kind=k, size="small")
        clfs[k].eval()
    except Exception as e:
        print(f"[skip {k}] {e}")

print(f"\n{'image':42} | " + " | ".join(f"{k:>10}" for k in clfs))
print("-"*42 + "-+-" + "-+-".join("-"*10 for _ in clfs))
for label, path in IMAGES.items():
    row = []
    for k, clf in clfs.items():
        try:
            p = clf(path, format="proba")
            p = float(p)
            row.append(f"{p:10.3f}")
        except Exception as e:
            row.append(f"{'ERR':>10}")
            print("err", k, e, file=sys.stderr)
    print(f"{label:42} | " + " | ".join(row))
print("\n(proba = P(belongs to that glasses class), threshold ~0.5)")

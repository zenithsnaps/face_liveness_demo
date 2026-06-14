"""Recalculate the glasses (sunglasses) score for every frame in a liveness
results CSV, using the SHIPPED tflite model on the WHOLE frame.

For each data row:
  - download the image at `summary_path` (cached on disk, concurrent fetch)
  - run glasses_sunglasses.tflite on the whole 256x256 frame -> P(sunglasses)
  - also run a Haar face detector (informational `face_found` only)

Appends 3 columns: glasses_sunglasses_proba, glasses_blocked, glasses_face_found.
Failed rows are retried once. Prints + writes a summary report.

Usage:
  python3 recalc_glasses_csv.py "results/FR_2026....csv"
"""
import os, sys, csv, math, shutil, hashlib, warnings
from concurrent.futures import ThreadPoolExecutor

warnings.filterwarnings("ignore")
csv.field_size_limit(10_000_000)

import numpy as np
import cv2
import requests
from PIL import Image
try:
    from ai_edge_litert.interpreter import Interpreter
except Exception:
    from tensorflow.lite import Interpreter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MODEL = os.path.join(ROOT, "assets", "models", "glasses_sunglasses.tflite")
CACHE = os.path.join(HERE, ".frame_cache")
SIZE = 256
THRESHOLD = 0.70  # lib/core/app_constants.dart: glassesBlockThreshold
WORKERS = 16

NEW_COLS = ["glasses_sunglasses_proba", "glasses_blocked", "glasses_face_found"]

# ---- model + face detector ------------------------------------------------
interp = Interpreter(model_path=MODEL); interp.allocate_tensors()
_inp = interp.get_input_details()[0]; _out = interp.get_output_details()[0]
_casc = cv2.CascadeClassifier(
    cv2.data.haarcascades + "haarcascade_frontalface_default.xml")


def _run(arr_rgb_256):  # (256,256,3) RGB float 0..255 -> NHWC -> P(sunglasses)
    # Shipped tflite expects NHWC (1,256,256,3) with preproc+sigmoid baked in.
    x = arr_rgb_256[None].astype(np.float32)
    interp.set_tensor(_inp["index"], x)
    interp.invoke()
    return float(interp.get_tensor(_out["index"]).reshape(-1)[0])


# ---- download (concurrent, cached) ----------------------------------------
def _cache_path(url):
    return os.path.join(CACHE, hashlib.sha1(url.encode()).hexdigest() + ".jpg")


def fetch(url):
    """Return local cached file path, or raise on failure."""
    p = _cache_path(url)
    if os.path.exists(p) and os.path.getsize(p) > 0:
        return p
    r = requests.get(url, timeout=30)
    r.raise_for_status()
    if not r.content:
        raise ValueError("empty body")
    tmp = p + ".tmp"
    with open(tmp, "wb") as f:
        f.write(r.content)
    os.replace(tmp, p)
    return p


def infer(path):
    """whole-frame proba + informational face_found bool."""
    img = Image.open(path).convert("RGB").resize((SIZE, SIZE))
    proba = _run(np.asarray(img, np.float32))
    if not math.isfinite(proba):
        raise ValueError("non-finite proba")
    bgr = cv2.imread(path)
    face_found = False
    if bgr is not None:
        h, w = bgr.shape[:2]
        gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
        faces = _casc.detectMultiScale(
            gray, 1.1, 4, minSize=(int(min(h, w) * 0.15),) * 2)
        face_found = len(faces) > 0
    return proba, face_found


def _download_one(idx, row):
    """Threaded: returns (idx, local_path_or_None, reason)."""
    url = (row.get("summary_path") or "").strip()
    if not url:
        return idx, None, "no_url"
    try:
        return idx, fetch(url), ""
    except Exception as e:
        return idx, None, f"download:{type(e).__name__}"


def run_pass(rows, indices, results, reasons, label):
    """Phase 1: download concurrently. Phase 2: infer SERIALLY in the main
    thread (TFLite interpreters are not thread-safe)."""
    # ---- phase 1: concurrent downloads ----
    paths = {}
    done = 0
    total = len(indices)
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for idx, path, reason in ex.map(
                lambda i: _download_one(i, rows[i]), indices):
            done += 1
            if path is not None:
                paths[idx] = path
            else:
                reasons[idx] = reason
            if done % 500 == 0 or done == total:
                print(f"  [{label}/dl] {done}/{total}", flush=True)

    # ---- phase 2: serial inference ----
    done = 0
    total2 = len(paths)
    for idx, path in paths.items():
        try:
            proba, face_found = infer(path)
            results[idx] = {
                "glasses_sunglasses_proba": f"{proba:.6f}",
                "glasses_blocked": "TRUE" if proba >= THRESHOLD else "FALSE",
                "glasses_face_found": "TRUE" if face_found else "FALSE",
            }
            reasons.pop(idx, None)
        except Exception as e:
            reasons[idx] = f"infer:{type(e).__name__}"
        done += 1
        if done % 500 == 0 or done == total2:
            print(f"  [{label}/infer] {done}/{total2}", flush=True)
    return [i for i in indices if i not in results]


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: recalc_glasses_csv.py <csv_path>")
    csv_path = sys.argv[1]
    if not os.path.isabs(csv_path):
        csv_path = os.path.join(os.getcwd(), csv_path)
    os.makedirs(CACHE, exist_ok=True)

    with open(csv_path, "r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        fieldnames = list(reader.fieldnames)
        rows = list(reader)
    print(f"Loaded {len(rows)} rows from {os.path.basename(csv_path)}")

    out_fields = fieldnames + [c for c in NEW_COLS if c not in fieldnames]

    results = {}   # idx -> {new col: value}
    reasons = {}   # idx -> failure reason (latest)

    # ---- pass 1 ----
    print("Pass 1 (all rows)...")
    failed = run_pass(rows, list(range(len(rows))), results, reasons, "pass1")
    n_fail1 = len(failed)
    print(f"Pass 1 done: {len(results)} ok, {n_fail1} failed")

    # ---- retry once ----
    recovered = 0
    if failed:
        print(f"Retry (once) on {n_fail1} failed rows...")
        before = set(results)
        run_pass(rows, failed, results, reasons, "retry")
        recovered = len(set(results) - before)
        print(f"Retry done: recovered {recovered}")

    still_failed = [i for i in range(len(rows)) if i not in results]

    # ---- backup + write ----
    bak = csv_path + ".recalc.bak"
    if not os.path.exists(bak):
        shutil.copy2(csv_path, bak)
        print(f"Backup written: {os.path.basename(bak)}")

    blank = {c: "" for c in NEW_COLS}
    with open(csv_path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=out_fields)
        writer.writeheader()
        for i, row in enumerate(rows):
            row.update(results.get(i, blank))
            writer.writerow(row)
    print(f"Wrote updated CSV: {os.path.basename(csv_path)}")

    # ---- summary ----
    n_blocked = sum(1 for r in results.values()
                    if r["glasses_blocked"] == "TRUE")
    n_noface = sum(1 for r in results.values()
                   if r["glasses_face_found"] == "FALSE")
    lines = []
    lines.append(f"CSV: {os.path.basename(csv_path)}")
    lines.append(f"Total rows:            {len(rows)}")
    lines.append(f"Succeeded:             {len(results)}")
    lines.append(f"Failed after pass 1:   {n_fail1}")
    lines.append(f"Recovered on retry:    {recovered}")
    lines.append(f"Still failed:          {len(still_failed)}")
    lines.append("")
    lines.append(f"glasses_blocked TRUE:  {n_blocked}")
    lines.append(f"glasses_blocked FALSE: {len(results) - n_blocked}")
    lines.append(f"face_found FALSE:      {n_noface}")
    if still_failed:
        lines.append("")
        lines.append("STILL-FAILED ROWS (id | reason | summary_path):")
        for i in still_failed:
            r = rows[i]
            lines.append(f"  {r.get('id','?')} | {reasons.get(i,'?')} | "
                         f"{(r.get('summary_path') or '').strip()}")
    report = "\n".join(lines)
    print("\n" + report)
    rp = os.path.join(HERE, "recalc_glasses_summary.txt")
    with open(rp, "w", encoding="utf-8") as f:
        f.write(report + "\n")
    print(f"\nSummary written: {rp}")
    print("ALL ROWS SUCCEEDED" if not still_failed
          else f"{len(still_failed)} ROW(S) STILL FAILED")


if __name__ == "__main__":
    main()

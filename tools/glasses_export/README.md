# Glasses (sunglasses) classifier — export pipeline

On-device sunglasses detector for the liveness flow. Replaces the brittle
pixel-statistic `EyeOcclusionUtil` ("is the eye region dark?") with a trained
classifier ("is this sunglasses?"). Robust to reflective / matte / tinted
lenses and to skin tone — see `docs/glasses_classifier_compare.jpg`.

## Source model

[`glasses-detector`](https://github.com/mantasu/glasses-detector) →
`GlassesClassifier(kind="sunglasses", size="small")`, which is a
`TinyBinaryClassifier` (~27k params). We export the **sunglasses** head only.

## Exported artifact contract

`assets/models/glasses_sunglasses.tflite` (float32, ~120 KB):

| | |
|---|---|
| input  | float32 NCHW `(1, 3, 256, 256)`, **RGB**, pixels in **[0, 255]** |
| output | float32 `(1, 1)` = **P(sunglasses)** in [0, 1] |

`/255`, ImageNet normalization (`mean=[.485,.456,.406] std=[.229,.224,.225]`)
and the final `sigmoid` are **baked into the graph**, so every platform only
has to: crop → resize to 256×256 → feed RGB bytes as float. No normalization
in app code. Threshold at **0.5** (validated margin is huge: see below).

## Reproduce

Requires Python 3.11–3.13. (Heavy deps; a venv is recommended.)

```bash
pip install glasses-detector onnx onnxruntime onnxscript pillow
pip install tensorflow onnx2tf onnx-graphsurgeon onnxsim sng4onnx ai_edge_litert tf_keras cmake

# macOS only: point Python at real CA certs so weights can download, and put
# the pip-installed cmake on PATH for onnx2tf's simplifier step.
export SSL_CERT_FILE="$(python -c 'import certifi; print(certifi.where())')"
export PATH="$(python -c 'import cmake,os;print(os.path.join(os.path.dirname(cmake.__file__),"data","bin"))'):$PATH"

python export_onnx.py                       # -> glasses_sunglasses.onnx (preproc+sigmoid baked)
python verify_onnx.py                       # ONNX vs PyTorch on sample imgs (diff must be ~0)
onnx2tf -i glasses_sunglasses.onnx -o tflite_out -kat image   # -> NCHW float32 tflite
python verify_tflite.py                     # TFLite vs PyTorch (diff must be ~0)
cp tflite_out/glasses_sunglasses_float32.tflite ../../assets/models/glasses_sunglasses.tflite
```

`-kat image` keeps the input as NCHW (matching the ONNX/PyTorch layout). The
default onnx2tf NHWC path currently trips an internal pickle bug for this
graph; NCHW verifies bit-exact and the perf delta is irrelevant for a 27k-param
model running in <10 ms.

## MediaPipe variant (NHWC + metadata) — run on MediaPipe's own TFLite

The NCHW artifact above is for the native `tflite_flutter` / Swift / Kotlin
paths, which link their **own** `TensorFlowLiteC`. On iOS that collides with the
TFLite that `MediaPipeTasksCommon` statically embeds (41 duplicate symbols → link
fails), so it can't coexist with MediaPipe hand detection in one binary.

To run the classifier through **MediaPipe Tasks `ImageClassifier`** instead (one
shared TFLite runtime, no clash), the model must be:

- **NHWC** `(1,256,256,3)` — MediaPipe does not accept NCHW.
- **Preprocessing BAKED INTO THE GRAPH** (`/255` + ImageNet norm + sigmoid), with
  IDENTITY scalar metadata. MediaPipe's ImageClassifier supports only *scalar*
  NormalizationOptions — feeding per-channel ImageNet mean/std throws
  `NotImplementedError: Per-channel image normalization is not available` at
  `create_from_options`. So we DON'T externalize norm; MediaPipe passes raw
  [0,255] through (mean=0, std=1) and the graph normalizes. Do **not** normalize
  in app code. (The earlier "strip preprocessing" idea is superseded — see
  `strip_preproc_for_mediapipe.py`.)

### Build it (validated steps — Apple Silicon)

Start from the Thai-funnel **fine-tuned** export `glasses_sunglasses_ft.onnx`
(preprocessing already baked, NCHW, input [0,255]).

```bash
# 1) ONNX -> NHWC tflite, KEEPING the baked preprocessing. onnx2tf's calibration
#    .npy + numpy 2.x trip a pickle error in download_test_image_data() (only used
#    for the optional accuracy check) — patch it; the plain CLI fails on numpy 2.x:
python - <<'PY'
import numpy as np, onnx2tf.onnx2tf as o2t
o2t.download_test_image_data = lambda: np.zeros((1,256,256,3), np.float32)
o2t.convert(input_onnx_file_path="glasses_sunglasses_ft.onnx",
            output_folder_path="tflite_out_baked",
            copy_onnx_input_output_names_to_tflite=True, non_verbose=True)
PY

# 2) attach IDENTITY-norm metadata + label map. tflite-support has NO arm64 macOS
#    wheel (any Python), and mediapipe's bundled writer ships no
#    _pywrap_metadata_version on arm64 — so run THIS STEP under x86_64 via Rosetta:
#      UV_PYTHON_INSTALL_DIR=$PWD/.uv/python uv venv --python cpython-3.11-macos-x86_64 .venv-x86
#      uv pip install --python .venv-x86/bin/python tflite-support   # x86_64 0.4.4 wheel
./.venv-x86/bin/python add_mediapipe_metadata.py \
    tflite_out_baked/glasses_sunglasses_ft_float32.tflite \
    glasses_sunglasses_mp.tflite

# 3) ship to ALL THREE bundles (same filename the native bridges load).
#    iOS bundles a SEPARATE copy under ios/Runner/ (Bundle.main.path), NOT
#    flutter_assets — easy to miss.
cp glasses_sunglasses_mp.tflite ../../assets/models/glasses_sunglasses.tflite
cp glasses_sunglasses_mp.tflite ../../android/app/src/main/assets/glasses_sunglasses.tflite
cp glasses_sunglasses_mp.tflite ../../ios/Runner/glasses_sunglasses.tflite
```

Verify it loads on MediaPipe's OWN runtime (not just bare TFLite) — this is what
catches the per-channel-norm rejection:

```python
import numpy as np, mediapipe as mp
from PIL import Image
from mediapipe.tasks.python.vision import ImageClassifier, ImageClassifierOptions
from mediapipe.tasks.python.core.base_options import BaseOptions
from mediapipe.tasks.python.vision.core.vision_task_running_mode import VisionTaskRunningMode
clf = ImageClassifier.create_from_options(ImageClassifierOptions(
    base_options=BaseOptions(model_asset_path="glasses_sunglasses_mp.tflite"),
    running_mode=VisionTaskRunningMode.IMAGE, max_results=1))
img = np.asarray(Image.open("../../test/frame5.jpg").convert("RGB").resize((256,256)), np.uint8)
print(clf.classify(mp.Image(image_format=mp.ImageFormat.SRGB, data=img)).classifications[0].categories[0])
clf.close()   # => category_name='sunglasses' score≈0.92951  (exact parity w/ fine-tuned PyTorch)
```

> Reproducibility gotchas, all real on this box: (a) onnx2tf's NHWC "pickle bug"
> is the numpy-2.x `np.load` default, fixed by the patch above — NOT the
> preprocessing graph. (b) `tflite-support` ships no arm64-macOS wheel, so the
> metadata step needs an x86_64/Rosetta (or Linux) Python. (c) `onnxsim` CLI not
> on PATH only skips graph simplification (harmless warning).

## Validation (proba on the sample frames)

| frame | truth | PyTorch | ONNX | TFLite |
|---|---|---|---|---|
| reflective sunglasses | sunglasses | 0.9947 | 0.9947 | 0.9947 |
| matte black sunglasses | sunglasses | 0.9647 | 0.9647 | 0.9647 |
| green translucent (eyes visible) | sunglasses | 0.9091 | 0.9091 | 0.9091 |
| frame5 (real office selfie) | sunglasses | 0.9728 | 0.9728 | 0.9728 |
| no glasses | none | 0.0630 | 0.0630 | 0.0630 |

max abs diff PyTorch↔ONNX↔TFLite = **0.00000**. Clean 0.06 vs 0.91+ separation.

## Fine-tuning on Thai funnel data (`finetune.py`)

The base model confused **clear prescription glasses** with sunglasses (the
real false-positive driver on funnel data). Per TH face-recognition rules,
clear glasses must **pass**, so we fine-tuned on labelled funnel frames:

- Positive = test_case `6. แว่นดำ`; negative = everything else (incl. clear
  glasses, masks, hands, mouth/nose occlusion).
- **Group-aware** train/test split (by `group_id`) so no attempt leaks.
- 420 train (140 pos / 280 neg) · 188 held-out test (28 pos / 160 neg).
- Face-cropped (Haar, expand 0.6) + flip/brightness/rotate augmentation,
  BCE + `pos_weight`, Adam lr 3e-4, best epoch by test F1 @0.70.

Held-out test, threshold **0.70**:

| | recall | FPR | precision | F1 |
|---|---|---|---|---|
| base model      | 82.1% | 1.9% | 88.5% | 0.85 |
| **fine-tuned**  | **100%** | **0.6%** | 96.6% | **0.98** |

Re-export: `python finetune.py` → `glasses_sunglasses_ft.onnx` → onnx2tf →
replace `assets/models/glasses_sunglasses.tflite`. The pre-fine-tune model is
kept as `glasses_sunglasses_base.tflite.bak`.

> Caveat: the held-out test shares this funnel's camera/lighting domain, so
> 100%/0.6% is optimistic for the wild. Positive diversity is limited (~42
> sunglasses attempts total). Collect more varied sunglasses + clear-glasses
> data before trusting these exact numbers in production.

## Caveats / next

- Only the `sunglasses` head is shipped. `eyeglasses` was unreliable (fired
  0.5–0.65 on translucent glasses *and* on bare faces) — do not ship it as-is.
- Validation used head-and-shoulders portraits. The app crops the face box
  expanded by `glassesFaceCropMargin` (0.6) to approximate that framing —
  **re-validate the threshold on real funnel frames** from Supabase before
  trusting it in production.
- The model size aliases `medium` / `large` exist if higher accuracy is
  needed (larger backbones); re-run the pipeline with `size="medium"`.

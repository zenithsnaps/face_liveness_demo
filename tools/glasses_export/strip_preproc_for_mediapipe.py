"""⚠️ SUPERSEDED — DO NOT USE for the MediaPipe build.

Stripping preprocessing requires MediaPipe to do per-channel ImageNet norm via
metadata, which MediaPipe ImageClassifier does NOT support
(`NotImplementedError: Per-channel image normalization is not available`). The
production MediaPipe model instead KEEPS preprocessing baked: run onnx2tf on the
original `glasses_sunglasses_ft.onnx` and use identity scalar metadata (see
add_mediapipe_metadata.py / README). Kept only for reference.

Make a MediaPipe-shaped ONNX from the FINE-TUNED export.

`glasses_sunglasses_ft.onnx` (produced by finetune.py) bakes the preprocessing
into its graph head:  Div(/255) -> Sub(mean) -> Div(std) -> Conv -> ... -> Sigmoid.

MediaPipe applies /255 + ImageNet normalize itself (from NormalizationOptions
metadata), so we strip those three leading nodes and feed the graph input
straight into the first Conv. The fine-tuned weights and the trailing sigmoid
are untouched — only the input-side preprocessing is externalized.

  python strip_preproc_for_mediapipe.py            # ft.onnx -> mp_ft.onnx
  python strip_preproc_for_mediapipe.py in.onnx out.onnx
"""
import sys
import onnx
import onnx_graphsurgeon as gs

SRC = sys.argv[1] if len(sys.argv) > 1 else "glasses_sunglasses_ft.onnx"
DST = sys.argv[2] if len(sys.argv) > 2 else "glasses_sunglasses_mp_ft.onnx"

graph = gs.import_onnx(onnx.load(SRC))
inp = graph.inputs[0]                       # 'image', (1,3,256,256), [0,255]

# First Conv currently consumes the normalized tensor (div_1). Rewire it to read
# the raw graph input; the Div/Sub/Div chain then dangles and cleanup() drops it.
first_conv = next(n for n in graph.nodes if n.op == "Conv")
first_conv.inputs[0] = inp

graph.cleanup().toposort()
onnx.save(gs.export_onnx(graph), DST)

kept = [n.op for n in graph.nodes[:3]]
print(f"wrote {DST}; first ops now {kept} (preprocessing removed)")

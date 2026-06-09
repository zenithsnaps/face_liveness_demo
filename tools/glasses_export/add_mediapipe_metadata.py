"""Attach MediaPipe-compatible TFLite metadata to the NHWC sunglasses model.

⚠️  MediaPipe ImageClassifier does NOT support per-channel image normalization —
`ImageClassifier.create_from_options` throws
`NotImplementedError: Per-channel image normalization is not available` when the
NormalizationOptions mean/std are 3-vectors. ImageNet normalization is inherently
per-channel, so we CANNOT externalize it to metadata.

Therefore the production MediaPipe model keeps `/255 + ImageNet norm + sigmoid`
BAKED INTO THE GRAPH (i.e. convert the original `glasses_sunglasses_ft.onnx`,
NOT the preprocessing-stripped variant), and this writer sets IDENTITY scalar
normalization (mean=0, std=1) — MediaPipe passes raw [0,255] float through and
the graph does the rest. Verified end-to-end via MediaPipe's own ImageClassifier
(frame5: 0.92951, exact parity with the fine-tuned PyTorch model).

Usage:
    onnx2tf -i glasses_sunglasses_ft.onnx -o tflite_out_baked     # baked, NHWC
    ./.venv-x86/bin/python add_mediapipe_metadata.py \
        tflite_out_baked/glasses_sunglasses_ft_float32.tflite \
        glasses_sunglasses_mp.tflite

Requires: pip install tflite-support, run under an x86_64 Python (no arm64-mac
wheel) — see README.
"""
import sys
from tflite_support.metadata_writers import image_classifier, writer_utils

# IDENTITY scalar normalization: MediaPipe feeds raw [0,255] float; the graph's
# baked Div(/255) + per-channel ImageNet Sub/Div handles normalization itself.
# (Per-channel mean/std here would be rejected by MediaPipe — see module docstring.)
_NORM_MEAN = [0.0]
_NORM_STD = [1.0]


def main(src: str, dst: str) -> None:
    # Single-label map: the sigmoid output is surfaced as this category's score.
    labels_path = "labels.txt"
    with open(labels_path, "w") as f:
        f.write("sunglasses\n")

    writer = image_classifier.MetadataWriter.create_for_inference(
        writer_utils.load_file(src),
        _NORM_MEAN, _NORM_STD,
        [labels_path],
    )
    writer_utils.save_file(writer.populate(), dst)
    print("wrote", dst)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: add_mediapipe_metadata.py <in.tflite> <out.tflite>")
    main(sys.argv[1], sys.argv[2])

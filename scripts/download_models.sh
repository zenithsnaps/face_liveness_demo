#!/usr/bin/env bash
# Download MediaPipe model files for the face liveness demo.
# Models are pulled from Google's public MediaPipe storage bucket.
#
# Usage: ./scripts/download_models.sh
# Re-running is safe (idempotent): existing files are kept unless you delete them first.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_ASSETS="$ROOT_DIR/android/app/src/main/assets"
FLUTTER_ASSETS="$ROOT_DIR/assets/models"

mkdir -p "$ANDROID_ASSETS" "$FLUTTER_ASSETS"

fetch() {
  local url="$1"
  local dest="$2"
  if [[ -f "$dest" ]]; then
    echo "✓ $dest already exists (skipping)"
    return
  fi
  echo "↓ Downloading $(basename "$dest")"
  curl -fsSL "$url" -o "$dest"
}

HAND_URL="https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
OBJ_URL="https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/float32/1/efficientdet_lite0.tflite"
FACE_LANDMARKER_URL="https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

# Android assets — loaded directly by tasks-vision via assetManager.
fetch "$HAND_URL"           "$ANDROID_ASSETS/hand_landmarker.task"
fetch "$OBJ_URL"            "$ANDROID_ASSETS/efficientdet_lite0.tflite"
fetch "$FACE_LANDMARKER_URL" "$ANDROID_ASSETS/face_landmarker.task"

# Flutter assets — mirror so you can also `rootBundle.load` from Dart if needed.
# (The iOS side requires these to be added to Runner.xcodeproj as bundle
# resources; the script cannot do that for you.)
fetch "$HAND_URL"           "$FLUTTER_ASSETS/hand_landmarker.task"
fetch "$OBJ_URL"            "$FLUTTER_ASSETS/efficientdet_lite0.tflite"
fetch "$FACE_LANDMARKER_URL" "$FLUTTER_ASSETS/face_landmarker.task"

echo
echo "✅ Models downloaded."
echo
echo "For iOS: open ios/Runner.xcworkspace in Xcode, drag the three files from"
echo "         $FLUTTER_ASSETS into the Runner folder, check 'Copy items if"
echo "         needed' and the Runner target — so MediaPipe can load them via"
echo "         Bundle.main.path(forResource:)."

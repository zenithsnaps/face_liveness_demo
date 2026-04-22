# face_liveness_demo

Flutter demo app that performs **on-device face pre-checks before sending a selfie to a backend face-recognition service**, built for a Thai-banking proof-of-concept context.

The app must pass five gates — in order — before it is willing to take a picture:

1. **Face fills the frame** (ML Kit Face Detection, bbox ratio vs oval guide)
2. **Smile challenge** (ML Kit smile probability crosses 0.2 → 0.7)
3. **Blink challenge** (ML Kit eye-open probability drops below 0.3 then rises above 0.7 on both eyes)
4. **No object blocking the face** (MediaPipe Object Detector bbox overlap + face landmark visibility)
5. **No hand/finger blocking the face** (MediaPipe Hand Landmarker — fingertips vs face bbox expanded 15%)

Once all five pass for five consecutive frames, the camera snaps a photo and navigates to a result screen.

---

## Architecture

```
presentation ─→ application ─→ domain
      │              │             ▲
      └──────────────┴─────────────┘
                     ▼
             infrastructure
```

- **`domain/`** — pure Dart. Value objects (`Rect2D`, `Point2D`, `Confidence`), entities (`FaceSnapshot`, `HandSnapshot`, `ObjectSnapshot`), abstract `FaceAnalyzer` / `HandAnalyzer` / `ObjectAnalyzer` repositories.
- **`application/`** — pure Dart. Five use cases (one per gate), a `RunPipeline` composer, and a `LivenessFlowMachine` that's a pure `(State, Event) → State` reducer.
- **`infrastructure/`** — Flutter side: `CameraFrameSource` wraps `package:camera`, `MlKitFaceAnalyzer` wraps `google_mlkit_face_detection`, and `MediaPipeChannel` ships frames to native via `MethodChannel('app.mymo/mediapipe')`.
- **`presentation/`** — Riverpod providers + Flutter widgets (oval overlay, banner, step indicator, camera screen).
- **Native** — Kotlin (`tasks-vision`) and Swift (`MediaPipeTasksVision`) bridges implement the MethodChannel contract, mirroring how a future pure-native port would call MediaPipe directly.

### Portability — the one rule

`domain/**` and `application/**` are **pure Dart**. No `package:flutter`, no `package:camera`, no ML Kit, no `dart:ui`, no `dart:io`. The CI grep in the Acceptance Criteria enforces this.

Porting to native means re-implementing only the three analyzer interfaces (Face / Hand / Object) plus the camera frame source — the business logic (gate thresholds, state machine, debouncing) translates to Swift/Kotlin virtually line-for-line.

---

## Setup

### 1. Prerequisites

- Flutter 3.19+ (Dart 3.3+)
- Xcode 15+ with iOS 15.5 deployment target
- Android Studio with `minSdk 24`

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Download MediaPipe models

```bash
./scripts/download_models.sh
```

This pulls `hand_landmarker.task` and `efficientdet_lite0.tflite` into:

- `android/app/src/main/assets/` (Android reads these at runtime)
- `assets/models/` (Flutter asset folder, mirrored)

### 4. iOS — manual steps (one-time)

1. `cd ios && pod install && cd ..` (first run only; pulls `MediaPipeTasksVision`).
2. Open `ios/Runner.xcworkspace` in Xcode.
3. Drag the four Swift files from `ios/Runner/MediaPipe/` (`MediaPipePlugin.swift`, `HandAnalyzerBridge.swift`, `ObjectAnalyzerBridge.swift`, `FrameDecoder.swift`) into the **Runner** group. Check:
   - ☑ Copy items if needed
   - ☑ Runner target
4. Drag `assets/models/hand_landmarker.task` and `assets/models/efficientdet_lite0.tflite` into the Runner group with the same options — MediaPipe loads them via `Bundle.main.path(forResource:)`.

### 5. Run

```bash
flutter run                      # default device
flutter run -d <device-id>       # specific device
```

Grant camera permission when prompted. The Thai prompt string is in `Info.plist`.

---

## Testing

```bash
flutter test                                                # run everything
flutter test test/features/face_liveness/application        # only the domain/app layer tests
```

All 30+ unit tests are pure Dart — no ML Kit, MediaPipe, camera, or Flutter widget dependencies in them. Boundary coverage for each gate: face bbox at 79%/80%/90%/98%/99%, yaw >15°, closed eyes, fingertip inside/just-outside face bbox, etc.

---

## Acceptance Criteria (from the spec)

Verified:

1. `grep -rE "package:(flutter|camera|google_mlkit)" lib/features/face_liveness/domain lib/features/face_liveness/application` → **zero matches**
2. `grep -rE "dart:(ui|io)" lib/features/face_liveness/domain lib/features/face_liveness/application` → **zero matches**
3. `flutter analyze` → **No issues found**
4. `flutter test` → **all tests pass**
5. Unit tests use fake analyzers — no real ML Kit / MediaPipe calls in tests
6. Five gates = five separate use case classes (`check_face_quality`, `check_liveness_smile`, `check_liveness_blink`, `check_no_object_occlusion`, `check_no_hand_occlusion`)
7. `LivenessFlowMachine.reduce` is pure: no `DateTime.now()`, no streams, no futures
8. Every abstract interface has one real implementation (`infrastructure/`) and one fake (`test/features/face_liveness/mocks/`)
9. Native MethodChannel handlers exist for both platforms (Kotlin `MediaPipePlugin.kt` + Swift `MediaPipePlugin.swift`)

---

## Porting to native (Swift / Kotlin) — the gist

Re-create, in the target language:

1. **Value objects + entities** — `Rect2D`, `Point2D`, `Confidence`, `FaceSnapshot`, `HandSnapshot`, `ObjectSnapshot`. These are roughly 200 lines of pure-data classes.
2. **Five use cases** — each is a function of `(inputs) → Result`. Thresholds live in `app_constants.dart` / `AppConstants.kt` / `AppConstants.swift`.
3. **State machine** — `LivenessFlowMachine.reduce(state, event)` maps 1:1 to Swift sealed enums + a switch.
4. **Analyzer interfaces** — `FaceAnalyzer` / `HandAnalyzer` / `ObjectAnalyzer`. On native, the implementations call ML Kit and MediaPipe directly (no MethodChannel needed).

Because none of the above depends on Flutter, the conversion is mechanical — the MethodChannel boundary in this demo is exactly where the Flutter ↔ native seam lives, so the native side is already doing the "real" work.

---

## Project layout

```
lib/
├── main.dart
├── core/
│   ├── result.dart                 # sealed Result<T,E>
│   ├── app_constants.dart          # all gate thresholds
│   └── app_strings.dart            # Thai strings
└── features/face_liveness/
    ├── domain/
    │   ├── entities/               # FaceSnapshot, HandSnapshot, ObjectSnapshot, FrameData...
    │   ├── value_objects/          # Rect2D, Point2D, Confidence, EulerAngles
    │   ├── failures/               # LivenessFailure + Thai messages
    │   └── repositories/           # abstract FaceAnalyzer / HandAnalyzer / ObjectAnalyzer
    ├── application/
    │   ├── usecases/               # 5 gates + RunPipeline composer
    │   └── flow/                   # state + event + pure reducer
    ├── infrastructure/
    │   ├── mlkit/                  # MlKitFaceAnalyzer
    │   ├── mediapipe/              # MediaPipe{Hand,Object}Analyzer
    │   ├── camera/                 # CameraFrameSource + InputImageConverter
    │   └── platform_channels/      # MediaPipeChannel
    └── presentation/
        ├── providers/              # Riverpod wiring
        ├── screens/                # Home, FaceLiveness, Result
        └── widgets/                # FaceOvalOverlay, StepIndicator, InstructionBanner

android/app/src/main/kotlin/com/example/face_liveness_demo/
├── MainActivity.kt
└── mediapipe/
    ├── MediaPipePlugin.kt          # MethodChannel dispatcher
    ├── FrameDecoder.kt             # NV21/YUV/BGRA → Bitmap
    ├── HandAnalyzerBridge.kt
    └── ObjectAnalyzerBridge.kt

ios/Runner/
├── AppDelegate.swift               # registers MediaPipePlugin
└── MediaPipe/
    ├── MediaPipePlugin.swift
    ├── FrameDecoder.swift          # BGRA/YUV → UIImage
    ├── HandAnalyzerBridge.swift
    └── ObjectAnalyzerBridge.swift
```

---

## Out of scope

No backend integration, no passive anti-spoofing (deepfake / 3D mask detection), no i18n beyond Thai, no analytics, no theming, no tablet layouts, no actual face recognition — the app returns a captured file path and that's it.

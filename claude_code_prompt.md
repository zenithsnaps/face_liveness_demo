# Claude Code Prompt: Face Liveness Pre-Check Demo App

Copy ทั้งหมดตั้งแต่ `===BEGIN PROMPT===` ไปจนถึง `===END PROMPT===` แล้ววางใน Claude Code

---

```
===BEGIN PROMPT===

# GOAL

Build a Flutter demo app that performs on-device face pre-checks BEFORE sending a selfie to a backend face-recognition service. The app must pass 5 gates before capturing a photo.

The app is a proof-of-concept for a Thai banking context (Thai-first UI). The core requirement is that **business logic must be portable** — the domain and application layers should contain pure Dart with zero dependencies on Flutter, camera, ML Kit, or MediaPipe, so the same logic can later be rewritten in Swift or Kotlin with minimal conceptual changes.

# THE 5 GATES (in order)

1. **Liveness check** — user is a real person, not a photo. Use ML Kit Face Detection signals:
   - Smile challenge (`smilingProbability` crosses 0.2 → 0.7 threshold)
   - Blink challenge (`eyeOpenProbability` drops below 0.3 then rises above 0.7 on both eyes)

2. **Face fills the frame** — face bounding box must occupy most of the oval guide. Use ML Kit Face Detection:
   - Face bbox width ≥ 90% of oval guide width (i.e., padding around face ≤ 10%)
   - If face bbox < 80% → "ขยับเข้าใกล้กล้อง"
   - If face bbox > 98% → "ขยับออกเล็กน้อย"

3. **No object blocking the face** — use Google AI Edge (MediaPipe) with two complementary signals:
   - **Object Detector task**: detect common objects (phone, cup, book, card) and check if any bbox overlaps the face bbox
   - **Face Landmarker visibility**: if landmark visibility scores in the nose/mouth regions drop below 0.7, flag as occluded

4. **No hand/finger blocking the face** — use Google AI Edge Hand Landmarker:
   - Detect hands (up to 2)
   - For each hand, check if ANY landmark (especially fingertips: indices 4, 8, 12, 16, 20) falls inside the face bbox expanded by 15%
   - If yes → fail with "ตรวจพบมือบังใบหน้า"

5. **Capture** — only when gates 1–4 all pass within the same frame window, take a photo and surface the file path to the caller.

# TECH STACK

- Flutter 3.19+ (latest stable)
- Dart 3.3+
- `flutter_riverpod` 2.6+ (use `Notifier` / `AsyncNotifier`, not legacy `StateNotifier`)
- `camera` 0.11+
- `google_mlkit_face_detection` 0.13+
- **Google AI Edge / MediaPipe**: accessed via **platform channels** (MethodChannel), NOT via any Flutter community plugin. This mirrors how native iOS/Android would call MediaPipe directly and makes porting trivial.
  - Android side: `com.google.mediapipe:tasks-vision` (Kotlin)
  - iOS side: `MediaPipeTasksVision` CocoaPod (Swift)

# NON-NEGOTIABLE ARCHITECTURE RULES

## Rule 1: Layered Clean Architecture

```
presentation ─→ application ─→ domain
      │              │             ▲
      └──────────────┴─────────────┘
                     ▼
             infrastructure
```

- `presentation/` imports `application/` + `domain/` (NOT infrastructure directly)
- `application/` imports `domain/` only
- `domain/` imports NOTHING external
- `infrastructure/` implements interfaces defined in `domain/`
- Providers in `presentation/` wire concrete infrastructure implementations to abstract domain interfaces

## Rule 2: Portability — `domain/` and `application/` are PURE DART

In `lib/features/face_liveness/domain/**` and `lib/features/face_liveness/application/**`:
- ❌ NO `import 'package:flutter/...'`
- ❌ NO `import 'package:camera/...'`
- ❌ NO `import 'package:google_mlkit_.../...'`
- ❌ NO `import 'dart:ui'` (means you must define your own `Rect2D`, `Point2D`, etc.)
- ❌ NO `import 'dart:io'`
- ✅ OK: `dart:core`, `dart:async`, `dart:math`, `package:meta`
- ✅ OK: `flutter_riverpod` ONLY inside providers, which live in `presentation/providers/` — not in application/domain layer files themselves

This constraint is enforced. When auditing your own code before finishing, grep for forbidden imports.

## Rule 3: All external SDKs hide behind abstract interfaces

Every external system (ML Kit, MediaPipe, camera) is accessed through an abstract class defined in `domain/repositories/`. The concrete implementation lives in `infrastructure/`. This allows:
- Swapping implementations
- Writing pure-Dart unit tests with mocks
- Porting to native by reimplementing only the infrastructure concept

## Rule 4: Platform channels for MediaPipe

Create a single `MediaPipeChannel` abstraction in `infrastructure/platform_channels/` that wraps MethodChannel calls. Native code lives at:
- `android/app/src/main/kotlin/com/example/face_liveness_demo/mediapipe/MediaPipePlugin.kt`
- `ios/Runner/MediaPipe/MediaPipePlugin.swift`

If full native implementation is out of scope for one Claude Code session, create a **stub implementation** that returns plausible fake data (e.g., "no hands detected", "no objects detected") BUT keep the channel contract and infrastructure wrapper complete and correct. Mark stubs with `// TODO(native):` comments.

# FOLDER STRUCTURE (create exactly this)

```
lib/
├── main.dart
├── core/
│   ├── result.dart                 # sealed Result<T, E> type
│   └── app_constants.dart
└── features/
    └── face_liveness/
        ├── domain/
        │   ├── entities/
        │   │   ├── face_snapshot.dart         # analyzer-agnostic face data
        │   │   ├── hand_snapshot.dart
        │   │   ├── object_snapshot.dart
        │   │   ├── frame_metadata.dart        # image size, rotation, timestamp
        │   │   └── liveness_gate.dart         # enum of the 5 gates
        │   ├── value_objects/
        │   │   ├── rect2d.dart                # pure Dart rect (NOT dart:ui Rect)
        │   │   ├── point2d.dart
        │   │   ├── euler_angles.dart
        │   │   └── confidence.dart            # 0..1 with validation
        │   ├── failures/
        │   │   └── liveness_failure.dart      # enum + Thai messages
        │   └── repositories/
        │       ├── face_analyzer.dart         # abstract
        │       ├── hand_analyzer.dart         # abstract
        │       └── object_analyzer.dart       # abstract
        ├── application/
        │   ├── usecases/
        │   │   ├── check_face_quality.dart    # Gate 2 + head pose + eyes
        │   │   ├── check_liveness_smile.dart  # Gate 1a
        │   │   ├── check_liveness_blink.dart  # Gate 1b
        │   │   ├── check_no_object_occlusion.dart  # Gate 3
        │   │   ├── check_no_hand_occlusion.dart    # Gate 4
        │   │   └── run_pipeline.dart          # composes the above
        │   └── flow/
        │       ├── liveness_flow_state.dart   # immutable state
        │       ├── liveness_flow_event.dart   # events the state machine consumes
        │       └── liveness_flow_machine.dart # pure state machine
        ├── infrastructure/
        │   ├── mlkit/
        │   │   └── mlkit_face_analyzer.dart   # implements FaceAnalyzer
        │   ├── mediapipe/
        │   │   ├── mediapipe_hand_analyzer.dart   # implements HandAnalyzer
        │   │   └── mediapipe_object_analyzer.dart # implements ObjectAnalyzer
        │   ├── camera/
        │   │   ├── camera_frame_source.dart   # wraps package:camera
        │   │   └── input_image_converter.dart # CameraImage → domain FrameMetadata + bytes
        │   └── platform_channels/
        │       └── mediapipe_channel.dart     # single MethodChannel
        └── presentation/
            ├── providers/
            │   └── liveness_providers.dart    # Riverpod DI wiring
            ├── screens/
            │   ├── home_screen.dart
            │   ├── face_liveness_screen.dart
            │   └── result_screen.dart
            └── widgets/
                ├── face_oval_overlay.dart     # CustomPainter
                ├── step_indicator.dart
                └── instruction_banner.dart

android/app/src/main/kotlin/com/example/face_liveness_demo/
├── MainActivity.kt
└── mediapipe/
    ├── MediaPipePlugin.kt                     # MethodChannel handler
    ├── HandAnalyzerBridge.kt                  # wraps HandLandmarker
    └── ObjectAnalyzerBridge.kt                # wraps ObjectDetector

ios/Runner/
├── AppDelegate.swift                          # register channel
└── MediaPipe/
    ├── MediaPipePlugin.swift
    ├── HandAnalyzerBridge.swift
    └── ObjectAnalyzerBridge.swift

test/
└── features/face_liveness/
    ├── application/
    │   ├── usecases/
    │   │   ├── check_face_quality_test.dart
    │   │   ├── check_no_hand_occlusion_test.dart
    │   │   └── check_no_object_occlusion_test.dart
    │   └── flow/
    │       └── liveness_flow_machine_test.dart
    └── mocks/
        ├── fake_face_analyzer.dart
        ├── fake_hand_analyzer.dart
        └── fake_object_analyzer.dart
```

# KEY DESIGN DETAILS

## Result type (`core/result.dart`)

```dart
sealed class Result<T, E> {
  const Result();
}
final class Ok<T, E> extends Result<T, E> {
  final T value;
  const Ok(this.value);
}
final class Err<T, E> extends Result<T, E> {
  final E error;
  const Err(this.error);
}
```

Use this for all analyzer returns. No throwing exceptions from domain/application.

## Abstract analyzer interfaces

```dart
// domain/repositories/face_analyzer.dart
abstract class FaceAnalyzer {
  Future<Result<FaceSnapshot?, AnalyzerError>> analyze(FrameData frame);
  Future<void> dispose();
}
```

`FrameData` is a pure-Dart container carrying image bytes, width/height, rotation, format. Infrastructure translates this to ML Kit's `InputImage` or MediaPipe's native image type.

## State machine (`application/flow/liveness_flow_machine.dart`)

States:
```
idle
  → initializing
  → waitingForFace          (gate 2: face quality)
  → livenessSmile           (gate 1a)
  → livenessBlink           (gate 1b)
  → finalOcclusionCheck     (gates 3 + 4)
  → capturing
  → done
  → failed(reason, retryable)
```

Events:
- `FrameAnalyzed(snapshot)`
- `TimeoutElapsed`
- `UserRetry`
- `CaptureComplete(photoPath)`

Pure function: `(State, Event) → State`. No Flutter, no async, no side effects.

## Debouncing

Require N=5 consecutive frames passing a gate before advancing. Prevents flicker from single-frame ML noise.

## Camera lifecycle

Handle `didChangeAppLifecycleState` correctly:
- `inactive` / `paused` → stop image stream, dispose controller
- `resumed` → re-init camera, resume stream
- `dispose` → always stop stream before disposing controller (disposing while streaming crashes on iOS)

## Platform channel contract

```dart
// infrastructure/platform_channels/mediapipe_channel.dart
class MediaPipeChannel {
  static const _channel = MethodChannel('app.mymo/mediapipe');

  Future<List<HandSnapshot>> detectHands(FrameData frame) { ... }
  Future<List<ObjectSnapshot>> detectObjects(FrameData frame) { ... }
  Future<void> initialize();
  Future<void> dispose();
}
```

Method names on the native side:
- `"initialize"` — load models
- `"detectHands"` — takes raw bytes + metadata, returns List<Map>
- `"detectObjects"` — same shape
- `"dispose"` — release resources

# UI / UX

- Thai-first UI text (hardcoded strings OK for demo, but keep them in one `app_strings.dart` file under `core/`)
- Full-screen camera preview with oval guide overlay
- Top banner: instruction / current gate status (red = fail, white = working, green = pass)
- Bottom: step indicator (3 dots: จัดใบหน้า → ยิ้ม & กระพริบตา → ตรวจการบัง)
- On capture, navigate to a result screen showing the captured photo path (for demo purposes)

Thai strings (use these exact wordings):
- "จัดใบหน้าให้อยู่ในกรอบ"
- "ขยับเข้าใกล้กล้อง"
- "ขยับออกเล็กน้อย"
- "กรุณามองตรงเข้ากล้อง"
- "กรุณาลืมตาทั้งสองข้าง"
- "กรุณายิ้ม"
- "กรุณากระพริบตา"
- "ตรวจพบมือบังใบหน้า กรุณาเอามือออก"
- "ตรวจพบสิ่งของบังใบหน้า"
- "ยืนยันตัวตนสำเร็จ"
- "ไม่พบใบหน้า"
- "พบใบหน้าหลายคน กรุณาถ่ายคนเดียว"

# SETUP REQUIREMENTS (include in README.md)

## Android
- `minSdkVersion 24` (MediaPipe Tasks requires 24+)
- Add camera permission to AndroidManifest.xml
- Add MediaPipe dependency to `android/app/build.gradle`:
  ```
  implementation 'com.google.mediapipe:tasks-vision:0.10.14'
  ```
- Download MediaPipe models and place in `android/app/src/main/assets/`:
  - `hand_landmarker.task`
  - `efficientdet_lite0.tflite` (or similar for object detection)

## iOS
- Deployment target: iOS 15.5
- Camera permission string in Info.plist
- Add to Podfile:
  ```
  pod 'MediaPipeTasksVision'
  ```
- Add model files to Xcode project as bundled resources

# ACCEPTANCE CRITERIA — verify before declaring done

1. ✅ Run `grep -rE "package:(flutter|camera|google_mlkit)" lib/features/face_liveness/domain lib/features/face_liveness/application` — must return ZERO matches
2. ✅ Run `grep -rE "package:(flutter|camera|google_mlkit)" lib/features/face_liveness/application` — must return ZERO matches (except allowed: `package:meta`)
3. ✅ `flutter analyze` returns no errors
4. ✅ All test files run and pass with `flutter test`
5. ✅ Unit tests use fake analyzers — no real ML Kit or MediaPipe calls in tests
6. ✅ The 5 gates are each implemented as a separate use case class
7. ✅ The state machine is a pure function (same input → same output, no I/O)
8. ✅ All abstract interfaces have at least one concrete implementation AND one fake for testing
9. ✅ README.md documents: setup steps, architecture diagram, how to port to native
10. ✅ Native platform channel handlers exist (either full implementation OR explicit stubs marked `// TODO(native):`)

# OUT OF SCOPE (do NOT build)

- Backend API integration — just return the file path
- Passive anti-spoofing (deepfake detection, 3D mask detection)
- Multi-language support beyond Thai (hardcoded strings are fine)
- Analytics / telemetry
- Dark/light theme switching
- Tablet layouts
- Face recognition itself (that's the backend's job)

# WORKING APPROACH

1. **Start by reading** this spec fully, then create the folder structure empty first so you have a scaffold
2. **Write domain layer first** (pure Dart, can test immediately)
3. **Write application layer + state machine** (pure Dart, can test immediately)
4. **Write tests for domain + application** BEFORE moving to infrastructure
5. **Write infrastructure stubs** (fake implementations of analyzers for now)
6. **Wire up Riverpod providers**
7. **Build presentation layer** (camera screen, overlay, flow)
8. **Replace ML Kit stub with real implementation**
9. **Replace MediaPipe stubs with platform channels** (native code LAST; if time-limited, leave as `// TODO(native):` with detailed comments about what each method should do)
10. **Run acceptance checklist** before finishing

When in doubt about a design decision, prioritize: (1) portability, (2) testability, (3) clarity. Ignore performance micro-optimizations for this demo.

Before finishing, run the grep commands in the acceptance criteria yourself and fix any violations.

===END PROMPT===
```

---

## 📋 จุดเด่นของ prompt นี้

### 1. บังคับ portability แบบมี enforcement
- กำหนด **grep command จริง** ที่ Claude Code ต้องรันเองเพื่อ audit
- บอกชัดว่า `dart:ui` ก็ห้าม (ต้องเขียน `Rect2D`, `Point2D` เอง) — จุดที่คนชอบพลาด

### 2. แยก abstraction ถูกจุด
```
FaceAnalyzer   ← ML Kit
HandAnalyzer   ← MediaPipe Hand Landmarker  
ObjectAnalyzer ← MediaPipe Object Detector
```
เวลา port ไป native: เขียนใหม่แค่ infrastructure layer

### 3. บังคับใช้ Platform Channel แทน Flutter plugin
- สำคัญมาก! เพราะ port ไป native คือการเรียก MediaPipe SDK ตรง
- ถ้าใช้ Flutter plugin จะได้ pattern ที่ไม่ตรงกับ native code

### 4. แยก state machine เป็น pure function
- Test ได้ทันทีด้วย pure Dart
- Port ไป Swift/Kotlin เป็น sealed class + function ตรงๆ

### 5. มี "fallback" สำหรับ native code
บอกชัดว่าถ้าเวลาไม่พอ ให้ใส่ `// TODO(native):` พร้อมคำอธิบายละเอียด — ไม่ให้ Claude Code ทำ half-baked implementation

### 6. Acceptance criteria ที่ verify ได้
10 ข้อที่ Claude Code ตรวจตัวเองได้ — ลดโอกาสส่งงานไม่ครบ

## 💡 Tips ก่อนใช้ prompt

1. **รันใน project ใหม่** — `flutter create face_liveness_demo` แล้วค่อยให้ Claude Code แก้ไข
2. **ถ้าใช้ใน MyMo SME repo เดิม** — แก้ path ใน prompt ให้ตรงกับ `features/face_liveness/` ตาม SDUI architecture ที่มีอยู่
3. **MediaPipe model files** — ต้อง download เองหลัง Claude Code สร้าง code เสร็จ (จาก https://developers.google.com/mediapipe/solutions/vision)
4. **รันเป็น phases** — ถ้า Claude Code หมด context ระหว่างทาง สามารถให้ทำทีละ phase ตาม "Working Approach" ข้อ 1-10

## 🔧 ถ้าอยากปรับ prompt เพิ่ม

- **เพิ่ม SDUI integration** — เพิ่ม section ว่าให้ wrap screen เป็น SDUI shelf/widget
- **เพิ่ม GoRouter** — เพิ่ม route declaration ตาม pattern ที่ MyMo SME ใช้
- **เพิ่ม error reporting** — เพิ่ม requirement ว่าให้ integrate กับ error tracking (Crashlytics/Sentry)

บอกได้ถ้าอยากให้ปรับส่วนไหนครับ

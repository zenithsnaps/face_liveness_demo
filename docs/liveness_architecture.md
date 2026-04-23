# Face Liveness Demo — สรุปสถาปัตยกรรมและการทำงาน

## 1. ภาพรวม (Overview)

Demo นี้เป็น Flutter app ที่ทำ **Face Liveness Detection** บน device โดยตรง (on-device ML) เพื่อยืนยันว่าผู้ใช้ที่อยู่หน้ากล้องเป็นมนุษย์จริง ไม่ใช่รูปภาพหรือหน้ากาก

เป้าหมายหลัก:
- ตรวจสอบคุณภาพใบหน้าในกรอบ oval
- ให้ผู้ใช้แสดง liveness challenge (ยิ้ม + กระพริบตา)
- ถ่ายภาพและตรวจสอบผลลัพธ์

---

## 2. โครงสร้างโปรเจกต์ (Project Structure)

```
lib/
├── core/                          # Shared utilities & constants
│   ├── app_constants.dart         # Thresholds, timeouts, debounce
│   ├── app_strings.dart           # Thai UI strings
│   └── result.dart                # Result<T,E> type (Ok/Err)
│
└── features/face_liveness/
    ├── domain/                    # Business rules (no framework deps)
    │   ├── entities/              # Core data models
    │   ├── value_objects/         # Typed primitives
    │   ├── repositories/          # Abstract interfaces
    │   └── failures/              # Error types
    │
    ├── application/               # Use cases & state machine
    │   ├── usecases/              # Stateless/stateful checks
    │   └── flow/                  # State machine (pure function)
    │
    ├── infrastructure/            # ML & camera implementations
    │   ├── camera/                # Camera stream + image conversion
    │   ├── mlkit/                 # Google ML Kit face analysis
    │   ├── mediapipe/             # MediaPipe hand/object/face
    │   ├── image/                 # JPEG decoding
    │   └── platform_channels/    # MethodChannel bridge
    │
    └── presentation/              # UI layer
        ├── screens/               # HomeScreen, FaceLivenessScreen, ResultScreen
        ├── widgets/               # FaceOvalOverlay, InstructionBanner, StepIndicator
        └── providers/             # Riverpod providers + FlowController

android/app/src/main/kotlin/…/mediapipe/   # Android native (Kotlin)
ios/Runner/MediaPipe/                       # iOS native (Swift)
assets/models/                             # TFLite + Task models
```

---

## 3. Stack

| Layer | เทคโนโลยี |
|-------|-----------|
| State Management | Riverpod 2.x (NotifierProvider) |
| Camera | `camera` package (CameraController) |
| Face Analysis | Google ML Kit Face Detection |
| Hand/Object/Face Detection | MediaPipe (via MethodChannel) |
| Architecture | Clean Architecture |
| Error Handling | `Result<T,E>` (Rust-style) |
| UI Language | Thai (th) |

---

## 4. Domain Entities

### FaceSnapshot
ข้อมูลใบหน้า 1 เฟรมจาก ML Kit

```dart
class FaceSnapshot {
  final Rect2D boundingBox;
  final EulerAngles headPose;       // yaw, pitch, roll (degrees)
  final double? smilingProbability;  // 0.0–1.0
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final Map<FaceLandmarkType, List<Point2D>> landmarks;  // 10 types
  final Map<FaceLandmarkType, double> landmarkVisibility; // occlusion score
}
```

### HandSnapshot
ข้อมูลมือ 1 ข้าง (21 landmark) จาก MediaPipe

```dart
class HandSnapshot {
  final List<Point2D> landmarks;  // 21 จุด ในพื้นที่ pixel
  final double confidence;
  final Handedness handedness;    // left / right / unknown
}
```

### ObjectSnapshot
วัตถุที่ตรวจพบจาก EfficientDet

```dart
class ObjectSnapshot {
  final Rect2D boundingBox;
  final String label;
  final double confidence;
}
```

### LivenessGate (enum)
ลำดับ gate ที่ต้องผ่าน:

```
faceQuality → livenessSmile → livenessBlink
```

---

## 5. State Machine

### States (Sealed Class)

```
FlowIdle
  ↓ StartRequested
FlowInitializing
  ↓ InitializationCompleted
FlowEvaluating(gate, consecutivePasses, lastFailure)
  ↓ FrameAnalyzed (5 consecutive passes)
FlowCapturing
  ↓ CaptureComplete
FlowDone(photoPath)

ข้อยกเว้น:
FlowEvaluating → FlowFailed   (timeout 20s หรือ capture validation ล้มเหลว)
FlowFailed     → FlowIdle     (UserRetry)
```

### State Machine Function

```dart
// Pure reducer — ไม่มี side effects
LivenessFlowState reduce(LivenessFlowState state, LivenessFlowEvent event)
```

### Debounce Logic (ใน FaceLivenessScreen)

```
frame pass  → consecutivePasses++
frame fail  → consecutivePasses = 0, บันทึก lastFailure
consecutivePasses >= 5  → ส่ง FrameAnalyzed(allPassed: true) → เลื่อน gate
timeout 20s → ส่ง TimeoutElapsed → FlowFailed
```

---

## 6. Liveness Pipeline

### การตรวจแต่ละ Gate (สิ่งที่รันจริง)

| Gate | Use Case | Model | หมายเหตุ |
|------|----------|-------|---------|
| faceQuality | CheckFaceQuality | ML Kit | stateless |
| livenessSmile | CheckLivenessSmile | ML Kit | stateful (track across frames) |
| livenessBlink | CheckLivenessBlink | ML Kit | stateful (track across frames) |

> ทุก gate ใช้ข้อมูลจาก ML Kit (`FaceSnapshot`) เพียงอย่างเดียว  
> `hands` และ `objects` ใน `PipelineFrameInput` ถูกส่งเป็น `const []` เสมอ — MediaPipe **ไม่ได้รันใน real-time stream**

### RunPipeline

```dart
// gate = faceQuality
PipelineFrameInput(face: faceSnapshot, hands: const [], objects: const [], …)
→ CheckFaceQuality

// gate = livenessSmile
→ CheckLivenessSmile (short-circuits ถ้า face == null)

// gate = livenessBlink
→ CheckLivenessBlink (short-circuits ถ้า face == null)
```

### CheckFaceQuality (stateless)

ตรวจ 4 เงื่อนไขตามลำดับ (fail-fast):

| ลำดับ | เงื่อนไข | Threshold | Failure |
|-------|---------|-----------|---------|
| 1 | พบใบหน้า | face != null | `noFace` |
| 2 | ขนาดใบหน้า | ≥ 90% ของความกว้าง oval (min 80%, max 98%) | `faceTooSmall` / `faceTooLarge` |
| 3 | center ใบหน้าอยู่ใน oval | ovalGuide.contains(face.center) | `faceOffCenter` |
| 4 | มุมหัว yaw / pitch / roll | ≤ ±15° ทุกแกน | `headPoseOff` |
| 5 | ตาทั้งสองข้างเปิด | min(leftEye, rightEye) > 0.5 | `eyesClosed` |

### CheckLivenessSmile (stateful)

```
ติดตาม state: notSmiling → smiling

smilingProbability < 0.2  → บันทึกว่า "ยังไม่ยิ้ม" (baseline)
smilingProbability > 0.7  → ถ้าผ่าน baseline แล้ว → PASS
```

### CheckLivenessBlink (stateful)

```
ติดตาม state: open → closed → open

leftEye < 0.3 AND rightEye < 0.3  → บันทึกว่า "ปิดตา"
leftEye > 0.7 AND rightEye > 0.7  → ถ้าผ่าน closed แล้ว → PASS
```

### CheckNoHandOcclusion / CheckNoObjectOcclusion (ยังไม่ได้ wire)

Use case ทั้งสองมีอยู่ในโค้ดและมี test ครอบคลุม แต่ **ยังไม่ได้ถูกเรียกใน `RunPipeline`** เนื่องจาก `hands` และ `objects` ถูก hardcode เป็น `const []` ใน `FaceLivenessScreen._process()`

Logic ที่เขียนไว้รอ wire:
- `CheckNoHandOcclusion`: ขยาย face bbox 15% แล้วตรวจว่า landmark มือ (21 จุด) อยู่ใน bbox หรือไม่
- `CheckNoObjectOcclusion`: ตรวจ object overlap > 10% ของ object area หรือ landmark visibility (nose/mouth) < 0.7

---

## 7. Post-Capture Validation

หลังถ่ายรูปสำเร็จ `ValidateCapture` ตรวจสอบซ้ำด้วย model อื่น:

```
1. decode JPEG → RGBA bytes
2. MediaPipeFaceDetectionAnalyzer.analyze()     [concurrent]
   → ต้องพบ face ≥ 1 ตัวที่ confidence ≥ 95%
3. MediaPipeHandAnalyzer.analyze()              [concurrent]
   → ต้องไม่พบมือ (confidence ≥ 0.5)
4. MediaPipeFaceLandmarkerAnalyzer.analyze()   [หลังผ่าน 2+3]
   → ดึง visibility score ของ landmark 4 จุด:
     noseBase (index 1), mouthLeft (61), mouthRight (291), mouthBottom (17)
5. CheckNoObjectOcclusion() — ตรวจ visibility drop ของ landmark รอบปาก/จมูก
   → ถ้า visibility < 0.7 บนจุดใดจุดหนึ่ง → LivenessFailure.objectOccluding
6. ถ้าผ่านทั้งหมด → CaptureComplete(path) → FlowDone
7. ถ้าไม่ผ่าน → CaptureFailed → FlowFailed
```

> real-time loop ยังคงเดิม — FaceLandmarker รันเฉพาะขั้น post-capture

---

## 8. Data Flow แบบ End-to-End

```
[ผู้ใช้กด Start]
      │
      ▼
FaceLivenessScreen (ConsumerStatefulWidget)
  ├─ initCamera()          CameraFrameSource.initialize()
  ├─ initMediaPipe()       MediaPipeChannel.initialize()
  └─ dispatch(StartRequested) → FlowInitializing

      │ InitializationCompleted
      ▼
FlowEvaluating(gate=faceQuality, passes=0)
      │
      │  ┌─────────────────── Camera stream loop ──────────────────────┐
      │  │                                                              │
      │  │  CameraImage                                                 │
      │  │      │                                                        │
      │  │      ▼                                                        │
      │  │  InputImageConverter                                          │
      │  │      ├─ → FrameData       (domain - raw bytes)               │
      │  │      └─ → InputImage      (ML Kit - rotation-aware)          │
      │  │                                                              │
      │  │  MlKitFaceAnalyzer.analyze(InputImage)   [ML Kit only]      │
      │  │      └─ → FaceSnapshot (or null)                             │
      │  │                                                              │
      │  │  RunPipeline.evaluate(gate, PipelineFrameInput)              │
      │  │      hands: const []  ← MediaPipe ไม่รันใน real-time        │
      │  │      objects: const [] ← MediaPipe ไม่รันใน real-time       │
      │  │      ├─ CheckFaceQuality              (gate=faceQuality)     │
      │  │      ├─ CheckLivenessSmile            (gate=livenessSmile)   │
      │  │      └─ CheckLivenessBlink            (gate=livenessBlink)   │
      │  │           └─ → PipelineFrameOutcome(passed/failed)           │
      │  │                                                              │
      │  │  dispatch(FrameAnalyzed(outcome))                            │
      │  │  consecutivePasses tracking (debounce 5 frames)             │
      │  └──────────────────────────────────────────────────────────────┘
      │
      │  (5 consecutive passes)
      ▼
FlowEvaluating(gate=livenessSmile, passes=0)
      │  (5 consecutive passes)
      ▼
FlowEvaluating(gate=livenessBlink, passes=0)
      │  (5 consecutive passes)
      ▼
FlowCapturing
      │
      ▼
CameraFrameSource.takePicture() → JPEG path
      │
      ▼
JpegFrameDecoder.decode() → RGBA bytes
      │
      ▼
ValidateCapture (MediaPipe face ≥95% + no hand)
      │
      ▼
FlowDone(photoPath) → ResultScreen
```

---

## 9. Infrastructure: ML Models

| Model | ใช้ที่ | Framework | ความถี่ |
|-------|--------|-----------|---------|
| ML Kit Face Detection | Real-time stream | Google ML Kit | ทุกเฟรม |
| blaze_face_short_range.tflite | Post-capture validate | MediaPipe TFLite | ครั้งเดียว (หลังถ่ายรูป) |
| hand_landmarker.task | Post-capture validate | MediaPipe Tasks | ครั้งเดียว (หลังถ่ายรูป) |
| face_landmarker.task | Post-capture validate | MediaPipe Tasks | ครั้งเดียว (หลังถ่ายรูป) |
| efficientdet_lite0.tflite | (ยังไม่ได้ใช้งาน) | MediaPipe TFLite | — |

### Platform Channel Bridge

```
Flutter (Dart)
    MediaPipeChannel.detectHands(frameData)
          │ MethodChannel: "app.mymo/mediapipe"
          ▼
Android: MediaPipePlugin.kt → HandAnalyzerBridge.kt
iOS:     MediaPipePlugin.swift → HandAnalyzerBridge.swift
          │ decode FrameData → Bitmap/UIImage → run model
          ▼
    [{landmarks: [[x,y]×21], confidence, handedness}]
          │ MethodChannel return
          ▼
Flutter → List<HandSnapshot>
```

### Frame Format per Platform

| Platform | Format | Conversion Path |
|----------|--------|-----------------|
| Android | NV21 | NV21 → JPEG → Bitmap |
| iOS | BGRA8888 | Direct CGContext (fastest) |

---

## 10. Class Relationships

```
Presentation
┌─────────────────────────────────────────────────────┐
│  FaceLivenessScreen                                 │
│    watches: flowControllerProvider (state)          │
│    reads:   cameraSourceProvider                    │
│             faceAnalyzerProvider                    │
│             pipelineProvider                        │
│             mediaPipeChannelProvider                │
│                                                     │
│  FlowController (Notifier)                          │
│    holds: LivenessFlowMachine                       │
│    state: LivenessFlowState                         │
│    dispatches events → reduce() → new state        │
└─────────────────────────────────────────────────────┘
              │
Application   │
┌─────────────────────────────────────────────────────┐
│  LivenessFlowMachine                                │
│    reduce(state, event) → state  [pure function]   │
│                                                     │
│  RunPipeline                                        │
│    ├─ CheckFaceQuality          [stateless]         │
│    ├─ CheckLivenessSmile        [stateful tracker]  │
│    └─ CheckLivenessBlink        [stateful tracker]  │
│                                                     │
│  (ยังไม่ได้ wire — use cases มีอยู่แต่ไม่ถูกเรียก) │
│    · CheckNoHandOcclusion       [stateless]         │
│    · CheckNoObjectOcclusion     [stateless]         │
│                                                     │
│  ValidateCapture                                    │
│    ├─ MediaPipeFaceDetectionAnalyzer                │
│    └─ HandAnalyzer                                  │
└─────────────────────────────────────────────────────┘
              │
Infrastructure│
┌─────────────────────────────────────────────────────┐
│  CameraFrameSource    (manages CameraController)    │
│  InputImageConverter  (CameraImage → FrameData)     │
│  MlKitFaceAnalyzer    (Face → FaceSnapshot)         │
│  MediaPipeHandAnalyzer  (via MediaPipeChannel)      │
│  MediaPipeObjectAnalyzer (via MediaPipeChannel)     │
│  MediaPipeFaceDetectionAnalyzer                     │
│  JpegFrameDecoder     (post-capture JPEG → RGBA)    │
└─────────────────────────────────────────────────────┘
```

---

## 11. UI Components

### FaceOvalOverlay (CustomPainter)

วาด oval guide บนหน้าจอ ขนาด **70% width × 55% height** ขยับขึ้น 5%
สี outline เปลี่ยนตาม OvalStatus:

| OvalStatus | สี | ความหมาย |
|-----------|-----|---------|
| neutral | ขาว | รอการตรวจสอบ |
| working | ขาว | กำลังตรวจ |
| success | #34C759 (เขียว) | ผ่านแล้ว |
| failure | #FF3B30 (แดง) | ตรวจไม่ผ่าน |

### InstructionBanner

แบนเนอร์บนสุด แสดงคำแนะนำภาษาไทยตาม gate ปัจจุบัน เช่น:
- "วางใบหน้าให้อยู่ในกรอบ"
- "กรุณายิ้ม"
- "กรุณากระพริบตา"

### StepIndicator

Progress dots 2 ขั้นตอน:
1. "จัดใบหน้า" (faceQuality gate)
2. "ยิ้ม & กระพริบตา" (smile + blink gates)

---

## 12. Error Handling

`LivenessFailure` enum มี 18 ประเภท พร้อม Thai error message เช่น:
- `faceNotFound` — ไม่พบใบหน้า
- `faceToSmall` — ใบหน้าเล็กเกินไป
- `faceTooLarge` — ใบหน้าใหญ่เกินไป
- `headPoseTilted` — กรุณาตรงหน้า
- `eyesClosed` — กรุณาลืมตา
- `handOccluding` — กรุณาเอามือออกจากใบหน้า
- `objectOccluding` — มีวัตถุบังใบหน้า
- `timeout` — หมดเวลา กรุณาลองใหม่
- `captureValidationFailed` — ถ่ายภาพไม่สำเร็จ

---

## 13. Constants (app_constants.dart)

```dart
// Face size limits
static const double targetFaceWidthRatio = 0.90;
static const double minFaceWidthRatio    = 0.80;
static const double maxFaceWidthRatio    = 0.98;

// Head pose
static const double maxHeadAngleDeg = 15.0;  // yaw/pitch/roll

// Eye
static const double minEyeOpenProb = 0.5;

// Smile
static const double smileActiveThreshold   = 0.7;
static const double smileInactiveThreshold = 0.2;

// Blink
static const double eyeClosedThreshold = 0.3;
static const double eyeOpenThreshold   = 0.7;

// Occlusion
static const double handBboxExpandRatio     = 0.15;
static const double objectOverlapThreshold  = 0.10;
static const double minLandmarkVisibility   = 0.70;

// Face landmarker (post-capture)
static const String faceLandmarkerModelAsset             = 'assets/models/face_landmarker.task';
static const double faceLandmarkerMinDetectionConfidence = 0.5;

// Flow
static const int   debounceFrames = 5;
static const int   gateTimeoutSec = 20;

// Post-capture
static const double minFaceDetectionScore = 0.95;
static const double minHandConfidence     = 0.50;
```

---

## 14. Tests

| Test File | ครอบคลุม |
|-----------|---------|
| `liveness_flow_machine_test.dart` | State transitions, debounce (5 frames), timeout, retry |
| `check_face_quality_test.dart` | Bbox ratio boundaries, head pose angles, eye openness |
| `check_no_hand_occlusion_test.dart` | Hand landmark ใน expanded bbox |
| `check_no_object_occlusion_test.dart` | Object overlap ratio, landmark visibility |

ทุก test ใช้ fake implementations:
- `FakeFaceAnalyzer`, `FakeHandAnalyzer`, `FakeObjectAnalyzer`
- `FaceSnapshotFixture` — สร้าง FaceSnapshot ด้วย parameter ที่กำหนด

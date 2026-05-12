# Face Liveness — Logic การตรวจสอบใบหน้า

## ภาพรวม

ระบบตรวจสอบ liveness ปัจจุบันใช้ **single-gate pipeline** (เหลือเพียง gate เดียวคือ Face Quality) ตามด้วย **post-capture validation** หลังถ่ายภาพ
gate ต้องผ่านติดต่อกัน **5 เฟรม** จึงนับว่าผ่าน และมี timeout **20 วินาที**

> **หมายเหตุประวัติ:** เดิมเคยมี 3 gate (Face Quality → Smile → Blink) แต่ตั้งแต่ commit `1a85f8f` เป็นต้นมา flow ถูกย่อให้เหลือ Face Quality อย่างเดียว (`LivenessGate.orderedPipeline = [faceQuality]`) — โค้ดของ smile / blink ยังอยู่ใน repo แต่ **unreachable** ไม่ถูกเรียกจริงในปัจจุบัน

---

## Flow ภาพรวม

```
[ผู้ใช้กด Start]
       ↓
[Initialize Camera + MediaPipe + ML Kit FaceLandmarker]
       ↓
┌─────────────────────────────────────────────────────────┐
│  REAL-TIME LOOP (~30 FPS)                               │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  GATE: Face Quality Check (stateless)            │   │
│  │  [ผ่าน 5 เฟรมติดต่อกัน หรือ timeout 20 วินาที]   │   │
│  │  (eye-check ภายใน gate ปิด/เปิดได้ผ่าน toggle)   │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
       ↓ ผ่าน
[ถ่ายภาพ JPEG]
       ↓
┌─────────────────────────────────────────────────────────┐
│  POST-CAPTURE VALIDATION (ทุก step ปิด/เปิดได้)         │
│  1. Hand analyzer → fail ถ้ามือบังหน้า (≥ 10%)          │
│  2. Face analyzer → fail ถ้า face score ต่ำกว่า threshold│
│  3. Eye occlusion (pixel analysis) → fail ถ้าตาถูกบัง   │
└─────────────────────────────────────────────────────────┘
       ↓
[ผ่าน → FlowDone] หรือ [ไม่ผ่าน → FlowFailed]
```

---

## GATE: Face Quality Check

**ประเภท:** Stateless (ตรวจทุกเฟรมอิสระ)
**ไฟล์:** `lib/features/face_liveness/application/usecases/check_face_quality.dart`

ตรวจสอบเงื่อนไขตามลำดับ แบบ fail-fast (หยุดทันทีที่ไม่ผ่านเงื่อนไขแรก)

| ลำดับ | เงื่อนไข | Threshold | Failure Code | ข้อความแสดง |
|-------|----------|-----------|--------------|-------------|
| 1 | ตรวจพบใบหน้า | `face != null` | `noFace` | ไม่พบใบหน้า |
| 2 | ความกว้างใบหน้า ≥ ขั้นต่ำ | ≥ 80% ของความกว้างกรอบ oval | `faceTooSmall` | ขยับเข้าใกล้กล้อง |
| 3 | ความกว้างใบหน้า ≤ สูงสุด | ≤ 98% ของความกว้างกรอบ oval | `faceTooLarge` | ขยับออกเล็กน้อย |
| 4 | ความกว้างใบหน้า ≥ target | ≥ 90% ของความกว้างกรอบ oval | `faceTooSmall` | ขยับเข้าใกล้กล้อง |
| 5 | ใบหน้าอยู่ตรงกลาง | center อยู่ใน oval guide | `faceOffCenter` | วางใบหน้าให้อยู่ในกรอบ |
| 6 | Head pose — Yaw / Pitch / Roll | `\|axis\| ≤ 15°` ทั้ง 3 แกน | `headPoseOff` | กรุณาตรงหน้า |
| 7 | มองเห็น eye landmarks *(เปิดเมื่อ `eyesEnabled = true`)* | `leftEye != null && rightEye != null` | `eyesNotVisible` | — |
| 8 | ตาเปิด *(เปิดเมื่อ `eyesEnabled = true`)* | `min(leftEyeOpen, rightEyeOpen) ≥ 0.7` | `eyesClosed` | กรุณาลืมตา |

**เกณฑ์ผ่าน:** ผ่านทุกเงื่อนไขที่เปิดอยู่ ติดต่อกัน **5 เฟรม**

### Pre-Capture Toggles

**ไฟล์:** `lib/features/face_liveness/application/usecases/pre_capture_checks.dart`

| Toggle | Default | ผลเมื่อปิด |
|--------|---------|-----------|
| `eyesEnabled` | `true` | ข้ามเงื่อนไข eye landmarks + eyes-open ทั้งสองข้อ |

ปรับได้จาก home screen ก่อนเริ่ม (provider: `pre_capture_checks_provider.dart`)

---

## Debounce & Gate Progression

**ไฟล์:** `lib/features/face_liveness/application/flow/liveness_flow_machine.dart`

```dart
// ทุกเฟรม:
IF outcome.didPass:
    consecutivePasses++
    IF consecutivePasses >= 5:   // AppConstants.debounceFrames
        → ถ้าเป็น gate สุดท้ายของ pipeline → FlowCapturing
        → ถ้าไม่ใช่ → ไป gate ถัดไป + reset
ELSE:
    consecutivePasses = 0
    lastFailure = reason         // โชว์เป็น UI hint
```

**วัตถุประสงค์ debounce:** กัน noise จากเฟรมเดียวที่อาจผ่านโดยบังเอิญ — ต้องผ่านต่อเนื่อง 5 เฟรมจึงนับ
เนื่องจากปัจจุบัน `orderedPipeline = [faceQuality]` ดังนั้นเมื่อ debounce ครบ → เข้าสู่ `FlowCapturing` ทันที

---

## Post-Capture Validation

**ไฟล์:** `lib/features/face_liveness/application/usecases/validate_capture.dart`

ทำงานหลังถ่ายภาพ ตรวจสอบตามลำดับแบบ fail-fast (เฉพาะ check ที่เปิดอยู่)
แต่ละ check จะ **early-return** เมื่อพบ failure แต่ผลที่ผ่านมาแล้ว (faceScores, handsDetected, ฯลฯ) ยังถูกส่งกลับมาเสมอ เพื่อให้ analytics screen ใช้ tune threshold ได้

### ลำดับการตรวจ

```
1. (เปิดเมื่อ faceEnabled)  Run face analyzer → ถ้า error → FAIL (analyzerError)
2. (เปิดเมื่อ handEnabled)  Run hand analyzer → ถ้า error → FAIL (analyzerError)
3. (เปิดเมื่อ handEnabled)  มีมือ confidence ≥ threshold → FAIL (handOccluding)
4. (เปิดเมื่อ faceEnabled)  ไม่มีหน้าที่ score ≥ threshold → FAIL (noFace)
5. (เปิดเมื่อ eyeOcclusionEnabled)  ตรวจตาด้วย pixel analysis → ถ้า occluded → FAIL (eyeOccluded)
6. ผ่านหมด → return success พร้อม faceScore + eyeEvidence
```

> **Failsafe:** ML Kit eye-contour analyzer ถ้า error หรือหา face ไม่เจอ ระบบจะ **ข้ามการตรวจ** (ไม่บล็อก) เพื่อกัน analyzer hiccup ทำให้ภาพดี ๆ fail

### Post-Capture Toggles

**ไฟล์:** `lib/features/face_liveness/application/usecases/post_capture_checks.dart`

| Toggle | Default | ผลเมื่อปิด |
|--------|---------|-----------|
| `faceEnabled` | `true` | ข้าม face analyzer + face-score check |
| `handEnabled` | `true` | ข้าม hand analyzer + hand-occlusion check |
| `eyeOcclusionEnabled` | `true` | ข้าม eye contour + pixel analysis |

ปรับได้จาก home screen (provider: `post_capture_checks_provider.dart`)

### Post-Capture Thresholds (runtime-tunable)

**ไฟล์:** `lib/features/face_liveness/application/usecases/post_capture_thresholds.dart`

| Threshold | Default (จาก `AppConstants`) |
|-----------|------------------------------|
| `faceScore` | **0.50** (50%) |
| `handConfidence` | **0.10** (10%) |
| `landmarkVisibility` | 0.7 *(ยังไม่ใช้ใน flow ปัจจุบัน)* |

ปรับได้จาก home screen ก่อนเริ่มเพื่อ A/B test threshold

---

## Eye Occlusion Check (Combined Score Model)

**ไฟล์หลัก:**
- `lib/features/face_liveness/application/usecases/check_no_eye_occlusion.dart` (orchestrator)
- `lib/features/face_liveness/application/utils/eye_occlusion_util.dart` (pixel logic)
- `lib/features/face_liveness/application/utils/eye_occlusion_thresholds.dart`

ใช้ **3 สัญญาณ pixel-level** วิเคราะห์บริเวณดวงตา (eye contour จาก ML Kit) เทียบกับ patch แก้ม
แต่ละสัญญาณให้ score 0.0 (pass) → 1.0 (block) แบบ linear interpolation ในช่วง suspicious

### สัญญาณที่ 1: Luminance Ratio (ความสว่างสัมพัทธ์)

```
lumRatio = eyeLuminance / cheekLuminance

score = 0.0   ถ้า lumRatio ≥ 0.55  (ตาสว่างพอ)
score = 1.0   ถ้า lumRatio ≤ 0.35  (ตามืดผิดปกติ)
score = (0.55 - lumRatio) / (0.55 - 0.35)   กรณีระหว่างกลาง
```

*Logic: แว่นดำทำให้บริเวณตาดูมืดกว่าแก้มมากผิดปกติ*

### สัญญาณที่ 2: Luminance StdDev (ความหลากหลาย/texture)

```
stdDev = standard deviation ของ luminance ในบริเวณตา

score = 0.0   ถ้า stdDev ≥ 15.0  (มี texture)
score = 1.0   ถ้า stdDev ≤ 8.0   (เรียบสม่ำเสมอ)
score = (15 - stdDev) / (15 - 8)   กรณีระหว่างกลาง
```

*Logic: เลนส์ทึบ = สีสม่ำเสมอ (variance ต่ำ) — ตาจริง = มี texture ม่านตา/ขนตา*

### สัญญาณที่ 3: Saturation (ความสดของสี)

```
saturation = mean(max(R,G,B) - min(R,G,B)) ต่อ pixel

score = 0.0   ถ้า saturation ≥ 20.0  (มีสี)
score = 1.0   ถ้า saturation ≤ 12.0  (ไม่มีสี/เทา)
score = (20 - saturation) / (20 - 12)   กรณีระหว่างกลาง
```

*Logic: เลนส์ดำ = สีเทาไม่มีสี — ม่านตามนุษย์มีสี*

### การตัดสินขั้นสุดท้าย

```
combinedScore_per_eye = (signal1 + signal2 + signal3) / 3
worstEye = max(leftEyeScore, rightEyeScore)

IF worstEye ≥ 0.5 → FAIL (eyeOccluded)
```

| Combined Score (ตาที่แย่ที่สุด) | ผล |
|---------------------------------|----|
| < 0.5 | ผ่าน — ตาไม่ถูกบัง |
| ≥ 0.5 | ไม่ผ่าน — ตรวจพบแว่นสีดำ/สิ่งบังตา |

ผลการวัด pixel ทั้งหมดถูกบันทึกใน `EyeOcclusionEvidence` (per-eye lumRatio / stdDev / saturation / score) เพื่อ replay บน analytics screen

---

## State Machine

**ไฟล์:** `lib/features/face_liveness/application/flow/liveness_flow_state.dart`

```
FlowIdle
    ↓ StartRequested
FlowInitializing
    ↓ InitializationCompleted
FlowEvaluating(gate=faceQuality, consecutivePasses=0)
    ↓ [ผ่าน 5 เฟรมติดต่อกัน]
FlowCapturing
    ↓ CaptureComplete(photoPath, faceScore)
FlowDone

─── Failure paths ───
FlowEvaluating + TimeoutElapsed (20s)    → FlowFailed(timeout, retryable=true)
FlowInitializing + InitializationFailed  → FlowFailed(reason, retryable=reason.isRetryable)
FlowCapturing + CaptureFailed(reason)    → FlowFailed(reason, retryable=true)
FlowFailed (retryable) + UserRetry       → FlowInitializing
```

State machine เป็น pure `(State, Event) → State` function — ไม่มี stream / timer / I/O ภายใน
test ได้ง่าย และ port ไป Swift / Kotlin ตรง ๆ ได้

---

## สรุป Failure Codes ทั้งหมด

| Code | สาเหตุ | สถานะการใช้งาน | Retryable |
|------|--------|----------------|-----------|
| `noFace` | ไม่พบใบหน้า | ✓ ใช้งานจริง | ✓ |
| `faceTooSmall` | หน้าเล็กเกิน (< 90% ของกรอบ) | ✓ | ✓ |
| `faceTooLarge` | หน้าใหญ่เกิน (> 98% ของกรอบ) | ✓ | ✓ |
| `faceOffCenter` | หน้าไม่อยู่กลางกรอบ oval | ✓ | ✓ |
| `headPoseOff` | หันหน้าเกิน ±15° | ✓ | ✓ |
| `eyesNotVisible` | มองไม่เห็น eye landmarks | ✓ (เมื่อ `eyesEnabled`) | ✓ |
| `eyesClosed` | ตาหลับขณะ face quality check | ✓ (เมื่อ `eyesEnabled`) | ✓ |
| `eyeOccluded` | ตรวจพบแว่นสีดำ/สิ่งบังตา (post-capture) | ✓ | ✓ |
| `handOccluding` | มือบังหน้า (post-capture) | ✓ | ✓ |
| `cameraError` | กล้องทำงานผิดปกติ | ✓ | ✓ |
| `analyzerError` | วิเคราะห์ภาพไม่ได้ | ✓ | ✓ |
| `timeout` | หมดเวลา 20 วินาทีต่อ gate | ✓ | ✓ |

> **หมายเหตุ:** ปัจจุบัน `LivenessFailure.isRetryable` คืน `true` กับทุก code (รวม `cameraError` / `analyzerError`) เพื่อให้ผู้ใช้ลองใหม่ได้เสมอ
| `multipleFaces` | พบหลายใบหน้า | ⚠ enum มีอยู่แต่ไม่ถูก raise ที่ไหน | ✓ |
| `smileNotDetected` | ไม่เห็นการเปลี่ยนจากไม่ยิ้มเป็นยิ้ม | ⚠ unreachable (gate ถูกถอด) | ✓ |
| `blinkNotDetected` | ไม่เห็นการกระพริบตา | ⚠ unreachable (gate ถูกถอด) | ✓ |
| `objectOccluding` | วัตถุบังหน้า | ⚠ unreachable (objects ถูก hardcode `const []`) | ✓ |

---

## Features ที่ยังไม่ได้เปิดใช้งาน / ยกเลิก

| Feature | สถานะ | หมายเหตุ |
|---------|-------|---------|
| Smile challenge gate | โค้ดยังอยู่แต่ unreachable | ถูกถอดออกจาก `orderedPipeline` (commit `1a85f8f`) |
| Blink challenge gate | โค้ดยังอยู่แต่ unreachable | ถูกถอดออกจาก `orderedPipeline` (commit `1a85f8f`) |
| Hand occlusion (real-time) | hardcoded `const []` | ตรวจเฉพาะ post-capture เท่านั้น (`face_liveness_screen.dart`) |
| Object occlusion (real-time) | hardcoded `const []` | ไม่ได้ wire เข้า pipeline จริง |
| Post-capture FaceLandmarker occlusion | TODO disabled | `validate_capture.dart` มี comment "FaceLandmarker occlusion check temporarily disabled" |

---

## Constants Reference

ค่า threshold ทั้งหมดอยู่ใน `lib/core/app_constants.dart`

```dart
// Face Quality (real-time gate)
faceBboxMinRatio              = 0.80   // 80% — ต่ำกว่านี้ = "ขยับเข้าใกล้"
faceBboxTargetRatio           = 0.90   // 90% — ขั้นต่ำที่ผ่านได้
faceBboxMaxRatio              = 0.98   // 98% — เกินนี้ = "ขยับออก"
headPoseMaxYawDegrees         = 15.0
headPoseMaxPitchDegrees       = 15.0
headPoseMaxRollDegrees        = 15.0
faceQualityEyeOpenMinThreshold = 0.7

// Smile & Blink (unreachable — โค้ดยังอยู่)
smileLowThreshold             = 0.2
smileHighThreshold            = 0.7
eyeClosedThreshold            = 0.3
eyeOpenThreshold              = 0.7

// Flow
debounceFrames                = 5
gateTimeout                   = 20 seconds

// Post-capture (default ของ PostCaptureThresholds; ปรับ runtime ได้)
faceDetectionMinScore         = 0.50
postCaptureHandMinConfidence  = 0.10

// Eye Occlusion (Combined Score model)
eyeLumRatioPass               = 0.55
eyeLumRatioBlock              = 0.35
eyeStdDevPass                 = 15.0
eyeStdDevBlock                = 8.0
eyeSaturationPass             = 20.0
eyeSaturationBlock            = 12.0
eyeOcclusionBlockScore        = 0.5

// Object / Hand (real-time — kept for reference, not wired)
landmarkVisibilityThreshold   = 0.7
objectBboxOverlapThreshold    = 0.1
objectDetectionMinConfidence  = 0.5
faceBboxExpansionForHand      = 0.15
handDetectionMinConfidence    = 0.5
maxHands                      = 2
```

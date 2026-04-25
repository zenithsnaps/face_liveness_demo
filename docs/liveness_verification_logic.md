# Face Liveness — Logic การตรวจสอบใบหน้า

## ภาพรวม

ระบบตรวจสอบ liveness ทำงานแบบ **3-gate pipeline** ที่ต้องผ่านตามลำดับ ตามด้วย **post-capture validation** หลังถ่ายภาพ
ทุก gate ต้องผ่านติดต่อกัน **5 เฟรม** จึงถือว่าผ่าน และแต่ละ gate มี timeout **20 วินาที**

---

## Flow ภาพรวม

```
[ผู้ใช้กด Start]
       ↓
[Initialize Camera + MediaPipe]
       ↓
┌─────────────────────────────────────────────────────────┐
│  REAL-TIME LOOP (~30 FPS)                               │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │  GATE 1: Face Quality Check (stateless)          │   │
│  │  [ผ่าน 5 เฟรมติดต่อกัน หรือ timeout 20 วินาที]  │   │
│  └──────────────────────────────────────────────────┘   │
│                         ↓ ผ่าน                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  GATE 2: Liveness Smile (stateful)               │   │
│  │  [ผ่าน 5 เฟรมติดต่อกัน หรือ timeout 20 วินาที]  │   │
│  └──────────────────────────────────────────────────┘   │
│                         ↓ ผ่าน                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  GATE 3: Liveness Blink (stateful)               │   │
│  │  [ผ่าน 5 เฟรมติดต่อกัน หรือ timeout 20 วินาที]  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
       ↓ ทุก gate ผ่าน
[ถ่ายภาพ JPEG]
       ↓
┌─────────────────────────────────────────────────────────┐
│  POST-CAPTURE VALIDATION                                │
│  1. Face detection score ≥ 50%                         │
│  2. ไม่มีมือบังหน้า (hand confidence < 10%)           │
│  3. ตาไม่ถูกบัง (pixel analysis)                      │
└─────────────────────────────────────────────────────────┘
       ↓
[ผ่าน → FlowDone] หรือ [ไม่ผ่าน → FlowFailed]
```

---

## GATE 1: Face Quality Check

**ประเภท:** Stateless (ตรวจทุกเฟรมอิสระ)
**ไฟล์:** `lib/features/face_liveness/application/usecases/check_face_quality.dart`

ตรวจสอบ 10 เงื่อนไขตามลำดับ แบบ fail-fast (หยุดทันทีที่ไม่ผ่านเงื่อนไขแรก)

| ลำดับ | เงื่อนไข | Threshold | Failure Code | ข้อความแสดง |
|-------|----------|-----------|--------------|-------------|
| 1 | ตรวจพบใบหน้า | `face != null` | `noFace` | ไม่พบใบหน้า |
| 2 | ความกว้างใบหน้า ≥ ขั้นต่ำ | ≥ 80% ของความกว้างกรอบ | `faceTooSmall` | ขยับเข้าใกล้กล้อง |
| 3 | ความกว้างใบหน้า ≥ target | ≥ 90% ของความกว้างกรอบ | `faceTooSmall` | ขยับเข้าใกล้กล้อง |
| 4 | ความกว้างใบหน้า ≤ สูงสุด | ≤ 98% ของความกว้างกรอบ | `faceTooLarge` | ขยับออกเล็กน้อย |
| 5 | ใบหน้าอยู่ตรงกลาง | center อยู่ใน oval guide | `faceOffCenter` | วางใบหน้าให้อยู่ในกรอบ |
| 6 | Head pose — Yaw (แกนซ้าย-ขวา) | `\|yaw\| ≤ 15°` | `headPoseOff` | กรุณาตรงหน้า |
| 7 | Head pose — Pitch (แกนบน-ล่าง) | `\|pitch\| ≤ 15°` | `headPoseOff` | กรุณาตรงหน้า |
| 8 | Head pose — Roll (แกนเอียง) | `\|roll\| ≤ 15°` | `headPoseOff` | กรุณาตรงหน้า |
| 9 | มองเห็น eye landmarks | `leftEye != null && rightEye != null` | `eyesNotVisible` | — |
| 10 | ตาเปิด | `min(leftEyeOpenProbability, rightEyeOpenProbability) ≥ 0.7` | `eyesClosed` | กรุณาลืมตา |

**เกณฑ์ผ่าน:** ผ่านทุกเงื่อนไขครบ 10 ข้อ ติดต่อกัน 5 เฟรม

---

## GATE 2: Liveness Smile Check

**ประเภท:** Stateful (จดจำสถานะข้ามเฟรม)
**ไฟล์:** `lib/features/face_liveness/application/usecases/check_liveness_smile.dart`

```
State: notSmiling → smiling

ทุกเฟรม:
  IF smilingProbability < 0.2
      → บันทึกว่าเคยเห็นหน้า "ไม่ยิ้ม" (recordedLowSmile = true)

  IF recordedLowSmile == true AND smilingProbability > 0.7
      → PASSED ✓
```

**Logic:** ต้องเห็นการเปลี่ยนแปลงจาก "หน้าปกติ" (< 0.2) ไปเป็น "ยิ้มชัดเจน" (> 0.7)
ป้องกันการนำรูปคนที่กำลังยิ้มอยู่แล้วมาหลอกระบบ

| Threshold | ค่า | ความหมาย |
|-----------|-----|----------|
| Low threshold | 0.2 | ต้องเห็นใบหน้าไม่ยิ้มก่อน |
| High threshold | 0.7 | ต้องยิ้มขึ้นมาเกิน 70% |

**เกณฑ์ผ่าน:** ผ่านสถานะ "smiling" ติดต่อกัน 5 เฟรม

---

## GATE 3: Liveness Blink Check

**ประเภท:** Stateful (จดจำสถานะข้ามเฟรม)
**ไฟล์:** `lib/features/face_liveness/application/usecases/check_liveness_blink.dart`

```
State: open → closed → open

ทุกเฟรม:
  IF leftEyeOpenProbability < 0.3 AND rightEyeOpenProbability < 0.3
      → บันทึกว่าเคยเห็นตาหลับ (recordedClosed = true)

  IF recordedClosed == true AND leftEyeOpenProbability > 0.7 AND rightEyeOpenProbability > 0.7
      → PASSED ✓
```

**Logic:** ต้องเห็นการกระพริบตาทั้งสองข้างพร้อมกัน ป้องกันรูปภาพนิ่ง

| Threshold | ค่า | ความหมาย |
|-----------|-----|----------|
| Closed threshold | 0.3 | ตาทั้งสองหลับ (probability < 30%) |
| Open threshold | 0.7 | ตาทั้งสองเปิด (probability > 70%) |

**เกณฑ์ผ่าน:** ผ่านสถานะ "ตาเปิดหลังจากหลับ" ติดต่อกัน 5 เฟรม

---

## Debounce & Gate Progression

**ไฟล์:** `lib/features/face_liveness/application/flow/liveness_flow_machine.dart`

```dart
// ทุกเฟรม:
IF outcome.didPass:
    consecutivePasses++
    IF consecutivePasses >= 5:   // AppConstants.debounceFrames
        → เลื่อนไป gate ถัดไป
        → reset consecutivePasses = 0
ELSE:
    consecutivePasses = 0
    lastFailure = reason         // แสดง UI message
```

**วัตถุประสงค์ debounce:** กัน noise จากเฟรมเดียวที่อาจผ่านโดยบังเอิญ — ต้องผ่านต่อเนื่อง 5 เฟรมจึงนับ

---

## Post-Capture Validation

**ไฟล์:** `lib/features/face_liveness/application/usecases/validate_capture.dart`

ทำงานหลังถ่ายภาพ ตรวจสอบตามลำดับแบบ fail-fast:

### ขั้นตอนที่ 1: Decode ภาพ
```
JPEG → RGBA byte array (FrameData)
```

### ขั้นตอนที่ 2: Face Detection Score (MediaPipe)
```
ตรวจจับใบหน้าทั้งหมดในภาพ
→ หา bestFace = face ที่มี score สูงสุด และ score ≥ 0.50
→ IF bestFace == null → FAIL (noFace)
```

| Threshold | ค่า |
|-----------|-----|
| Minimum face detection score | **0.50** (50%) |

### ขั้นตอนที่ 3: Hand Occlusion Check
```
ตรวจจับมือในภาพ (ทำพร้อมกับ face detection)
→ กรอง: มือที่ confidence ≥ 0.10
→ IF พบมือที่ผ่าน threshold → FAIL (handOccluding)
```

| Threshold | ค่า |
|-----------|-----|
| Hand confidence minimum | **0.10** (10%) |

### ขั้นตอนที่ 4: Eye Occlusion Check (Pixel Analysis)

ใช้ **3 สัญญาณ pixel-level** วิเคราะห์บริเวณดวงตา เพื่อตรวจหาแว่นดำหรือสิ่งบังตา
แต่ละสัญญาณให้ score 0.0 (pass) → 1.0 (block) แบบ linear interpolation

#### สัญญาณที่ 1: Luminance Ratio (ความสว่างสัมพัทธ์)

```
lumRatio = eyeLuminance / cheekLuminance

score = 0.0   ถ้า lumRatio ≥ 0.55  (ตาสว่างพอ)
score = 1.0   ถ้า lumRatio ≤ 0.35  (ตามืดผิดปกติ)
score = (0.55 - lumRatio) / (0.55 - 0.35)   กรณีระหว่างกลาง
```

*Logic: แว่นดำทำให้บริเวณตาดูมืดกว่าแก้มมากผิดปกติ*

#### สัญญาณที่ 2: Luminance StdDev (ความหลากหลาย/texture)

```
stdDev = standard deviation ของ luminance ในบริเวณตา

score = 0.0   ถ้า stdDev ≥ 15.0  (มี texture)
score = 1.0   ถ้า stdDev ≤ 8.0   (เรียบสม่ำเสมอ)
score = (15 - stdDev) / (15 - 8)   กรณีระหว่างกลาง
```

*Logic: เลนส์ทึบ = สีสม่ำเสมอ (variance ต่ำ) ตาจริง = มี texture ม่านตา*

#### สัญญาณที่ 3: Saturation (ความสดของสี)

```
saturation = mean(max(R,G,B) - min(R,G,B)) ต่อ pixel

score = 0.0   ถ้า saturation ≥ 20.0  (มีสี)
score = 1.0   ถ้า saturation ≤ 12.0  (ไม่มีสี/เทา)
score = (20 - saturation) / (20 - 12)   กรณีระหว่างกลาง
```

*Logic: เลนส์ดำ = สีเทาไม่มีสี ม่านตา = มีสี*

#### การตัดสินขั้นสุดท้าย

```
combinedScore = (signal1 + signal2 + signal3) / 3   [คำนวณต่อตาแต่ละข้าง]
worstEye = max(leftEyeScore, rightEyeScore)

IF worstEye ≥ 0.5 → FAIL (eyeOccluded)
```

| Combined Score | ผล |
|---------------|----|
| < 0.5 | ผ่าน — ตาไม่ถูกบัง |
| ≥ 0.5 | ไม่ผ่าน — ตรวจพบแว่นสีดำ/สิ่งบังตา |

---

## State Machine

**ไฟล์:** `lib/features/face_liveness/application/flow/liveness_flow_state.dart`

```
FlowIdle
    ↓ StartRequested
FlowInitializing
    ↓ InitializationCompleted
FlowEvaluating(gate=faceQuality, consecutivePasses=0)
    ↓ [ผ่าน 5 เฟรม]
FlowEvaluating(gate=livenessSmile, consecutivePasses=0)
    ↓ [ผ่าน 5 เฟรม]
FlowEvaluating(gate=livenessBlink, consecutivePasses=0)
    ↓ [ผ่าน 5 เฟรม]
FlowCapturing
    ↓ CaptureComplete(photoPath, faceScore)
FlowDone

─── Failure paths ───
[gate ใดก็ตาม] + TimeoutElapsed (20s)  → FlowFailed(timeout, retryable=true)
[InitializationFailed]                  → FlowFailed(cameraError, retryable=false)
[Post-capture fail]                     → FlowFailed(reason, retryable=true)
[UserRetry]                             → กลับไป FlowEvaluating(gate=faceQuality)
```

---

## สรุป Failure Codes ทั้งหมด

| Code | สาเหตุ | Retryable |
|------|--------|-----------|
| `noFace` | ไม่พบใบหน้า | ✓ |
| `multipleFaces` | พบหลายใบหน้า | ✓ |
| `faceTooSmall` | หน้าเล็กเกิน (< 90% ของกรอบ) | ✓ |
| `faceTooLarge` | หน้าใหญ่เกิน (> 98% ของกรอบ) | ✓ |
| `faceOffCenter` | หน้าไม่อยู่กลางกรอบ oval | ✓ |
| `headPoseOff` | หันหน้าเกิน ±15° | ✓ |
| `eyesNotVisible` | มองไม่เห็น eye landmarks | ✓ |
| `eyesClosed` | ตาหลับขณะ face quality check | ✓ |
| `smileNotDetected` | ไม่เห็นการเปลี่ยนจากไม่ยิ้มเป็นยิ้ม | ✓ |
| `blinkNotDetected` | ไม่เห็นการกระพริบตา | ✓ |
| `objectOccluding` | วัตถุบังหน้า (ยังไม่เปิดใช้งาน) | ✓ |
| `eyeOccluded` | ตรวจพบแว่นสีดำ/สิ่งบังตา | ✓ |
| `handOccluding` | มือบังหน้า | ✓ |
| `cameraError` | กล้องทำงานผิดปกติ | ✗ |
| `analyzerError` | วิเคราะห์ภาพไม่ได้ | ✗ |
| `timeout` | หมดเวลา 20 วินาทีต่อ gate | ✓ |

---

## Features ที่ยังไม่ได้เปิดใช้งาน

| Feature | สถานะ | หมายเหตุ |
|---------|-------|---------|
| Hand occlusion (real-time) | โค้ดพร้อม แต่ไม่ได้ wire ใน pipeline | `hands` hardcoded เป็น `const []` |
| Object occlusion (real-time) | โค้ดพร้อม แต่ไม่ได้ wire ใน pipeline | `objects` hardcoded เป็น `const []` |
| Eye contour analyzer | TODO | ใช้ fallback skin-patch แทน |

---

## Constants Reference

ค่า threshold ทั้งหมดอยู่ใน `lib/core/app_constants.dart`

```dart
// Face Quality
faceBboxMinRatio              = 0.80   // 80%
faceBboxTargetRatio           = 0.90   // 90%
faceBboxMaxRatio              = 0.98   // 98%
headPoseMaxYawDegrees         = 15.0
headPoseMaxPitchDegrees       = 15.0
headPoseMaxRollDegrees        = 15.0
faceQualityEyeOpenMinThreshold = 0.7

// Smile & Blink
smileLowThreshold             = 0.2
smileHighThreshold            = 0.7
eyeClosedThreshold            = 0.3
eyeOpenThreshold              = 0.7

// Flow
debounceFrames                = 5
gateTimeout                   = 20 seconds

// Post-capture
faceDetectionMinScore         = 0.50
postCaptureHandMinConfidence  = 0.10

// Eye Occlusion (pixel analysis)
eyeLumRatioPass               = 0.55
eyeLumRatioBlock              = 0.35
eyeStdDevPass                 = 15.0
eyeStdDevBlock                = 8.0
eyeSaturationPass             = 20.0
eyeSaturationBlock            = 12.0
eyeOcclusionBlockScore        = 0.5
```

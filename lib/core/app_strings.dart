class AppStrings {
  const AppStrings._();

  // Home
  static const String appTitle = 'ยืนยันตัวตนด้วยใบหน้า';
  static const String startVerification = 'เริ่มยืนยันตัวตน';
  static const String homeSubtitle = 'โปรดเตรียมพร้อมถ่ายภาพใบหน้าในที่ที่มีแสงสว่างเพียงพอ';

  // Oval / face positioning
  static const String frameYourFace = 'จัดใบหน้าให้อยู่ในกรอบ';
  static const String moveCloser = 'ขยับเข้าใกล้กล้อง';
  static const String moveFarther = 'ขยับออกเล็กน้อย';
  static const String lookStraight = 'กรุณามองตรงเข้ากล้อง';
  static const String openEyes = 'กรุณาลืมตาทั้งสองข้าง';

  // Liveness challenges
  static const String pleaseSmile = 'กรุณายิ้ม';
  static const String pleaseBlink = 'กรุณากระพริบตา';

  // Occlusion — failure messages (shown when occlusion detected)
  static const String handCoveringFace = 'ตรวจพบมือใน frame กรุณาเอามือออกจากกล้อง';
  static const String objectCoveringFace = 'ตรวจพบสิ่งของบังใบหน้า กรุณาเอาออก';

  // Occlusion — gate instructions (shown when gate is active but no issue detected yet)
  static const String checkHandOcclusion = 'กรุณาแน่ใจว่าไม่มีมือบังใบหน้า';
  static const String checkObjectOcclusion = 'กรุณาแน่ใจว่าไม่มีสิ่งของบังใบหน้า';

  // Result
  static const String verificationSuccess = 'ยืนยันตัวตนสำเร็จ';
  static const String noFaceDetected = 'มีวัตถุบังบนใบหน้า';
  static const String multipleFaces = 'พบใบหน้าหลายคน กรุณาถ่ายคนเดียว';

  // Flow
  static const String preparing = 'กำลังเตรียมกล้อง...';
  static const String capturing = 'กำลังถ่ายภาพ...';
  static const String verifying = 'กำลังตรวจสอบ...';
  static const String retry = 'ลองใหม่';
  static const String done = 'เสร็จสิ้น';
  static const String photoPathLabel = 'ไฟล์ภาพ:';
  static const String faceScoreLabel = 'คะแนนตรวจสอบใบหน้า:';
  static const String captureFailedTitle = 'ตรวจสอบไม่ผ่าน';
  static const String captureFailedSubtitle = 'ผลการตรวจสอบภาพหลังถ่าย';

  // Step indicator
  static const String stepFrame = 'จัดใบหน้า';
  static const String stepLiveness = 'ยิ้ม & กระพริบตา';
  static const String stepOcclusion = 'ตรวจการบัง';

  // Cloud sync status (shown on ResultScreen)
  static const String cloudUpload = 'อัพโหลดขึ้น cloud';
  static const String cloudRetry = 'ลองอัพโหลดอีกครั้ง';
  static const String cloudSaving = 'กำลังบันทึกขึ้น cloud...';
  static const String cloudSaved = 'บันทึกขึ้น cloud แล้ว';
  static const String cloudSyncFailed = 'บันทึกขึ้น cloud ไม่สำเร็จ';
}

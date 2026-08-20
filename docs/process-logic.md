# Process Logic — โหมดเรียลไทม์ และ โหมดวิดีโอ

> เอกสารนี้อธิบายลำดับการทำงานจริงในโค้ด ต้องแก้ให้ตรงทุกครั้งที่แก้ท่อประมวลผล
> ตรวจสอบล่าสุดกับโค้ดในบรานช์ `claude/setting-functionality-check-6wnrba`

ทั้งสองโหมดใช้โมเดลชุดเดียวกัน (`traffic` + `number`) และแกนกลางชุดเดียวกัน
(`DetectionStabilizer`, `SignalInterpreter`, `CountdownAlertController`,
`SignNumberPipelineService`, `CountdownReadingStabilizer`, `VoiceAlertController`)
ต่างกันที่การจัดการเวลา: **วิดีโอยอมช้าแต่ต้องครบ / เรียลไทม์ยอมขาดแต่ต้องสด**

---

## โหมดเรียลไทม์ (หน้าหลัก)

`camera_inference_controller.dart`

1. **รับสตรีม** — `onStreamingData` ปฏิเสธทันทีถ้ากล้องไม่ active แล้วแปลงเป็น
   `RealtimeFramePacket` (เก็บ `originalImage` เฉพาะเฟรมที่มี `sign_number`)
2. **คิวเฟรมล่าสุด** — `LatestFrameQueue` ประมวลผลทีละเฟรม เฟรมที่ค้างอยู่ถูกทิ้ง
   และนับไว้ที่ `droppedCount`
3. **ด่านความสด** — `RealtimeFrameFreshnessGuard` ตัด `stale` (เก่ากว่า 1500ms) และ
   `outOfOrder` (frameNumber ย้อน)
4. **ตรวจจับ** — กรอง confidence รายคลาส:
   - `sign_number` → `realtimeSignConfidenceThreshold` (0.25) คงที่
   - คลาสอื่น → ค่าจากผู้ใช้ ผ่าน `DetectionAlertConfig.effectiveConfidenceThreshold`
     ซึ่ง **บังคับเพดาน 0.5 กับคลาสที่เกี่ยวกับความปลอดภัย** (แดง/เหลือง/`off_light`/`dont_*`)
   → `DetectionStabilizer.update` → `SignalInterpreter.interpret` (แบนเนอร์คำสั่งคนขับ)
   และ `VoiceAlertController.handleEvents` (เสียง)
5. **อ่านเลข** — `RealtimeNumberInferenceEngine.process` ผ่านด่าน 5 ชั้น
   (enabled / มี `sign_number` / โมเดลพร้อม + มี `frameBytes` / ไม่มีงานค้าง / พ้นช่วง throttle)
   โดย `enabled` มาจาก **งบเวลา**: เฟรมที่ใช้เวลาไปแล้วเกิน
   `realtimeNumberInferenceAgeBudgetRatio` (60%) ของ `maximumFrameAge` จะถูกข้าม
   เพราะอ่านเสร็จก็ไม่ทันใช้ (ไม่ใช่การกันไฟเขียวอย่างที่เอกสารเก่าเข้าใจ)
6. **ตรวจอายุอีกครั้ง** — เฟรมที่เกิน `maximumFrameAge` ตอนประมวลผลเสร็จ ผลจะถูกทิ้ง
   และจอถูกล้าง ผลลัพธ์ของขั้นนี้ป้อนกลับเข้า `RealtimeLoadGovernor`
7. **ถือเลข** — `CountdownReadingHold` (1.5 วินาที) คงเลขล่าสุดไว้ระหว่างที่อ่านไม่ได้
   แล้วปล่อยทิ้งเมื่อหมดเวลา
8. **นับถอยหลัง** — `CountdownAlertController.update` สร้างข้อความ UI และ event เสียง
   (ช่วง ≤ 5 วินาที) เลขเดียวกันถูกส่งเข้า `SignalInterpreter` เป็น `countdownNumberText`
   ทำให้แบนเนอร์อ่านว่า "ไฟแดง - เตรียมออกตัว อีก N วินาที"

### กรอบบนภาพกล้อง

`YOLOView` ฝั่ง native วาดกรอบและชื่อคลาส (ภาษาอังกฤษ) จาก **ผลดิบรายเฟรม** ที่ threshold
ระดับ native (≤ 0.25) จึงขึ้นก่อนที่ stabilizer จะยืนยันและไม่ตรงกับสิ่งที่แอปประกาศ
ค่าเริ่มต้นจึงปิดไว้ (`SettingsProvider.showDetectionOverlay` = false) และเปิดได้จากหน้า Settings
สำหรับตอนทดสอบ/สาธิต โดยส่งต่อผ่าน `applyDetectionSettings` → `setShowOverlays`
ช่องทางสื่อสารกับคนขับคือแบนเนอร์ไทยและเสียงเท่านั้น

### กลไกทนทานของโหมดเรียลไทม์

| กลไก | ไฟล์ | ทำอะไร |
| --- | --- | --- |
| `RealtimeLoadGovernor` | `data/services/realtime_load_governor.dart` | ถอยความถี่อ่านเลข (400ms → สูงสุด 1600ms) เมื่อทำไม่ทันติดกัน แล้วค่อยกลับมาเมื่อไหว |
| งบเวลาก่อนอ่านเลข | `camera_inference_controller.dart` | ไม่เริ่มงานที่รู้อยู่แล้วว่าจะเสร็จไม่ทัน |
| Watchdog 200ms | `expireStaleResults` | ล้างจอเมื่อไม่มีเฟรมเข้ามา |
| กู้สตรีมอัตโนมัติ | `_maybeRequestStreamRestart` | เงียบเกิน 3 วินาที → สั่งหน้าจอสร้าง `YOLOView` ใหม่ เว้นระยะ 5 วินาที สูงสุด 3 ครั้ง แล้วบอกผู้ใช้ให้เปิดแอปใหม่ |

---

## โหมดวิดีโอ (เครื่องมือทดสอบ)

`video_inference_controller.dart`

1. เลือกไฟล์ → `VideoInputValidator` (≤ 100 MB และ `ffprobe` อ่านได้จริง)
2. FFmpeg สกัดเฟรม `fps=4, scale=640` — 1 เฟรมที่สกัด = 1 เฟรมที่ predict
3. ต่อเฟรม: โมเดล `traffic` (conf 0.25 / IoU 0.45 คงที่) → ถ้ามี `sign_number` เข้า
   `SignNumberPipelineService` → `CountdownReadingStabilizer` → `CountdownHoldTracker`
   (3 เฟรม = 0.75 วินาที) → เก็บลง `frameResults[index]` พร้อม `signPresent`
4. เล่นวิดีโอ: `frameIndex = ms × targetFps ÷ 1000`
   - `isSeekJump` (ถอยหลัง **หรือ** กระโดดหน้าเกิน 2 วินาที) → `_resetDetectionSession`
   - เฟรมที่ไม่มีผล (วิเคราะห์ไม่สำเร็จ) → **ข้ามไปเฉย ๆ** ไม่ป้อน list ว่างเข้า stabilizer
     เพราะ "ไม่รู้" ไม่เท่ากับ "ไม่เจออะไร"
5. `DetectionStabilizer.update` ด้วย timestamp ของ **เวลาในวิดีโอ** → `SignalInterpreter` +
   `CountdownAlertController` → `VoiceAlertController`

การกรอง confidence ฝั่ง Dart ใช้กติกาเดียวกับเรียลไทม์ (ค่าผู้ใช้ + เพดานความปลอดภัย)
เพื่อให้คลิปเดียวกันดูสองโหมดแล้วเทียบกันได้

---

## ระบบเสียง (ใช้ร่วมกัน)

`VoiceAlertController` พูดครั้งละหนึ่งข้อความเสมอ แต่ **ไม่ทิ้ง event ที่ยังพูดไม่ได้**:

- คิวเก็บคลาสละหนึ่งรายการ (ตัวใหม่ทับตัวเก่า) หมดอายุตาม `pendingRetention`
- `lost` ล้างคลาสนั้นออกจากคิว, สถานะไฟใหม่ลบสถานะไฟเก่าที่ยังค้าง
- event ที่ priority สูงกว่า **ตัดคิว** ข้อความที่กำลังพูดผ่าน `interruptSpeech`
  (หยุดประโยคเดิมก่อน ไม่ได้พูดซ้อน)
- event นับถอยหลังที่พูดไม่สำเร็จถูก re-arm ด้วย `allowThresholdEventRetry()`

สัญญาณที่เป็นจริงพร้อมกัน (เช่นไฟแดง + ลูกศรตรงไป) ถูกรวมเป็น **ประโยคเดียว** ภายในหน้าต่าง
`combineWindow` สูงสุด `maximumCombinedClasses` รายการ ยกเว้นสถานะไฟด้วยกันเองที่รวมไม่ได้
(ไฟเป็นจริงได้ทีละสถานะ) สัญญาณที่เกิดคนละจังหวะยังพูดแยกประโยคตามคิวเหมือนเดิม

เหตุผลที่ต้องมีคิว: `DetectionStabilizer` ยิง `detected`/`changed` **ครั้งเดียว** ต่อการ
เปลี่ยนสถานะ ถ้าตอนนั้นระบบเสียงไม่ว่างแล้วทิ้ง event ไป ไฟแดงดวงนั้นจะไม่ถูกประกาศเลย

---

## ตารางเทียบค่าคงที่

| รายการ | เรียลไทม์ | วิดีโอ |
| --- | --- | --- |
| อัตราตรวจจับ | native 15/วิ, ส่งกลับ 10/วิ | 4/วิ |
| ความละเอียด | 1280×960 | กว้าง 640 |
| conf ไฟจราจร (ฝั่ง Dart) | ค่าผู้ใช้ + เพดาน 0.5 | ค่าผู้ใช้ + เพดาน 0.5 |
| conf ที่ส่งให้โมเดล | ≤ 0.25 (native ต้องเห็นตั้งแต่ต่ำ) | 0.25 |
| ความถี่อ่านเลข | 400ms (ถอยได้ถึง 1600ms) | ทุกเฟรมที่เจอป้าย |
| การถือเลข | `CountdownReadingHold` 1.5 วินาที | `CountdownHoldTracker` 3 เฟรม |
| `offLightMinimumFrames` | 30 (≈3 วินาทีที่ 10fps) ปรับได้ในหน้า Settings | 12 (=3 วินาทีที่ 4fps) |
| แหล่งเวลา | นาฬิกาจริง (`_clock()`) | ตำแหน่งวิดีโอ |
| FPS ที่แสดง | `currentFps` = เฟรมที่ Dart ประมวลผลจริง (`nativeInferenceFps` แยกไว้ต่างหาก) | — |

---

## ข้อจำกัดที่ยังเหลืออยู่ (ยังไม่ได้แก้)

- **ต้นทุนการส่งภาพข้าม platform channel** — `includeOriginalImage: true` เป็นค่าระดับ
  config ฝั่ง native จึงส่งภาพทุกเฟรมไม่ว่าจะใช้หรือไม่ การเก็บ `frameBytes` เฉพาะเฟรมที่มี
  `sign_number` ประหยัดแค่หน่วยความจำฝั่ง Dart เท่านั้น การลด `inferenceFrequency`
  (ตอนนี้ 15 ขณะที่ส่งกลับแค่ 10) น่าจะช่วยเรื่องความร้อน แต่ **ต้องวัดบนเครื่องจริงก่อน**
  จึงยังไม่เปลี่ยน
- **ความละเอียดและอัตราเฟรมของสองโหมดยังต่างกัน** ตามข้อจำกัดของแต่ละท่อ ป้ายไกล ๆ
  ในโหมดวิดีโอจึงยังเล็กเกินกว่าโมเดลตัวเลขจะอ่านออกในบางคลิป
- **การ map เฟรมของโหมดวิดีโอ** อาศัยสมมติฐานว่าเฟรมที่ FFmpeg สกัดเรียงตรงกับเวลาจริง
  ตัวกรอง `fps` ของ FFmpeg คืนผลเป็น CFR อยู่แล้วจึงรองรับ VFR ได้ระดับหนึ่ง แต่คลิปที่มี
  start PTS ไม่เท่ากับศูนย์ยังมีโอกาสเลื่อน

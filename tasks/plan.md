# Implementation Plan: อัปเดตโมเดลจาก GitHub Release โดยไม่สร้าง APK ใหม่

## ภาพรวม

เพิ่มระบบตรวจสอบและดาวน์โหลดโมเดลใหม่จาก GitHub Release โดยให้โมเดลใน `assets/models/` เป็น fallback เสมอ แอปจะอ่าน manifest ระยะไกล เปรียบเทียบเวอร์ชัน ดาวน์โหลดเป็นไฟล์ชั่วคราว ตรวจ SHA-256 แล้วสลับไปใช้ไฟล์ใหม่แบบ atomic เฉพาะเมื่อทุกขั้นตอนสำเร็จ หากเครือข่ายหรือโมเดลใหม่มีปัญหา แอปต้องกลับไปใช้โมเดลเดิมหรือ bundled model ได้

## สถาปัตยกรรมที่เลือก

- ใช้ Release asset ชื่อคงที่ `model_manifest.json` และเรียกผ่าน `https://github.com/Kitsada-007/Mobile-ML-App/releases/latest/download/model_manifest.json` เพื่อให้ URL ตรวจสอบเวอร์ชันไม่เปลี่ยน
- ใช้ชื่อไฟล์โมเดลที่มีเวอร์ชัน เช่น `traffic_model_v1_2_0.tflite` เพื่อไม่ชนกับไฟล์ cache เดิม
- เก็บโมเดลที่ดาวน์โหลดใน application documents ภายใต้ `models/<model-id>/<version>/`
- ดาวน์โหลดเป็น `.part` และ rename เป็น `.tflite` หลัง SHA-256 ตรงเท่านั้น
- บันทึก active version/path หลังไฟล์ผ่านการตรวจสอบแล้วเท่านั้น
- `ModelManager` เลือก downloaded model ก่อน แล้ว fallback ไปยังโมเดลใน `assets/models/`
- repository ต้องเป็น public สำหรับ direct download; ถ้าเป็น private ห้ามฝัง GitHub token ใน APK และต้องใช้ backend/proxy ที่ควบคุมสิทธิ์แทน

## รูปแบบ Release

Release tag ตัวอย่าง: `model-v1.2.0`

ไฟล์ที่แนบ:

```text
model_manifest.json
traffic_model_v1_2_0.tflite
number_model_v1_2_0.tflite
```

ตัวอย่าง `model_manifest.json`:

```json
{
  "schemaVersion": 1,
  "releaseVersion": "1.2.0",
  "minimumAppVersion": "1.1.2",
  "models": {
    "traffic": {
      "version": "1.2.0",
      "fileName": "traffic_model_v1_2_0.tflite",
      "url": "https://github.com/Kitsada-007/Mobile-ML-App/releases/download/model-v1.2.0/traffic_model_v1_2_0.tflite",
      "sha256": "<64 lowercase hexadecimal characters>",
      "sizeBytes": 12345678
    },
    "number": {
      "version": "1.2.0",
      "fileName": "number_model_v1_2_0.tflite",
      "url": "https://github.com/Kitsada-007/Mobile-ML-App/releases/download/model-v1.2.0/number_model_v1_2_0.tflite",
      "sha256": "<64 lowercase hexadecimal characters>",
      "sizeBytes": 12345678
    }
  }
}
```

## Dependency Graph

```text
Release assets + remote manifest
              |
              v
Manifest models/parser
              |
              v
HTTP download + SHA-256 + atomic storage
              |
              v
Active-model registry
              |
              v
ModelManager path selection + bundled fallback
              |
              v
Startup/background update trigger + UI status
```

## Task 1: กำหนด manifest contract

**Description:** สร้าง Dart model สำหรับ parse และ validate manifest โดยแยก `traffic` และ `number` ชัดเจน

**Acceptance criteria:**

- [ ] ปฏิเสธ manifest ที่ขาด field, schema ไม่รองรับ, SHA-256 ไม่ใช่ hex 64 ตัว หรือ URL ไม่ใช่ HTTPS
- [ ] parse `version`, `fileName`, `url`, `sha256`, `sizeBytes` ได้ครบ
- [ ] ปฏิเสธชื่อไฟล์ที่มี `..`, `/` หรือ `\` เพื่อป้องกัน path traversal

**Verification:** unit tests สำหรับ valid/invalid manifest

**Dependencies:** None

**Files likely touched:**

- `lib/core/models/model_manifest.dart`
- `test/core/models/model_manifest_test.dart`

**Estimated scope:** Small

## Task 2: เพิ่ม remote manifest client

**Description:** ดาวน์โหลด `model_manifest.json` จาก URL ล่าสุดด้วย timeout และจำกัดขนาด response

**Acceptance criteria:**

- [ ] HTTP 200 เท่านั้นจึงนำข้อมูลไป parse
- [ ] timeout, offline, redirect ผิดปลายทาง และ JSON เสียคืนผลลัพธ์แบบ recoverable
- [ ] ไม่ทำให้ startup ของแอป crash

**Verification:** tests ด้วย mock HTTP client สำหรับ success, non-200, timeout และ malformed JSON

**Dependencies:** Task 1

**Files likely touched:**

- `lib/services/model_update_client.dart`
- `test/services/model_update_client_test.dart`

**Estimated scope:** Small

## Task 3: เพิ่ม downloader และตรวจ SHA-256

**Description:** ดาวน์โหลดโมเดลแบบ streaming ลง `.part`, จำกัดขนาด, คำนวณ SHA-256 และ promote เป็นไฟล์จริงเมื่อถูกต้อง

**Acceptance criteria:**

- [ ] ไม่โหลดไฟล์โมเดลทั้งหมดเข้าหน่วยความจำพร้อมกัน
- [ ] ลบ `.part` เมื่อ download, size หรือ checksum ล้มเหลว
- [ ] rename เป็นไฟล์จริงเฉพาะเมื่อ `sizeBytes` และ SHA-256 ตรง

**Verification:** tests สำหรับไฟล์ถูกต้อง, checksum ผิด, download ขาดช่วง และไฟล์เกินขนาด

**Dependencies:** Task 1

**Files likely touched:**

- `lib/services/model_file_store.dart`
- `test/services/model_file_store_test.dart`

**Estimated scope:** Medium

## Checkpoint: หลัง Task 1-3

- [ ] parser/client/downloader tests ผ่าน
- [ ] ไฟล์เสียไม่สามารถกลายเป็น active model
- [ ] offline path ไม่ throw ออกจาก update flow

## Task 4: เพิ่ม active-model registry และ version comparison

**Description:** เก็บ version/path/checksum ของโมเดลที่ active แยกตาม model id และเปรียบเทียบ semantic version โดยไม่ใช้ string comparison ธรรมดา

**Acceptance criteria:**

- [ ] `1.10.0` ใหม่กว่า `1.9.0`
- [ ] registry ไม่ชี้ไปยังไฟล์ที่ไม่มีอยู่หรือ checksum ไม่ตรง
- [ ] commit ค่า active หลังดาวน์โหลดสำเร็จเท่านั้น

**Verification:** unit tests สำหรับ version ordering, missing file และ corrupted preferences

**Dependencies:** Task 3

**Files likely touched:**

- `lib/services/model_registry.dart`
- `test/services/model_registry_test.dart`

**Estimated scope:** Medium

## Task 5: เชื่อม update orchestration เข้ากับ ModelManager

**Description:** เพิ่ม flow `check -> compare -> download -> verify -> activate` และปรับ `getModelPath()` ให้เลือก downloaded model ก่อน bundled model

**Acceptance criteria:**

- [ ] ไม่มี network ยังเปิดกล้องด้วย bundled model ได้
- [ ] โมเดลใหม่ที่ verified ถูกเลือกในการเปิด inference ครั้งถัดไป
- [ ] ถ้า downloaded model เปิดใช้งานไม่สำเร็จ registry ถูก rollback และใช้ previous/bundled model

**Verification:** service tests ครอบคลุม updated, already-current, offline, checksum-failed และ rollback

**Dependencies:** Tasks 2, 4

**Files likely touched:**

- `lib/services/model_updater.dart`
- `lib/services/model_manager.dart`
- `lib/core/models/models.dart`
- `test/services/model_updater_test.dart`

**Estimated scope:** Medium

## Task 6: เรียกตรวจอัปเดตโดยไม่ขวาง startup

**Description:** เริ่มแอปด้วยโมเดล local ทันที แล้วตรวจ update แบบ background หนึ่งครั้งต่อ session พร้อมป้องกัน download ซ้ำ

**Acceptance criteria:**

- [ ] หน้า inference ไม่ต้องรอ network
- [ ] มี update เพียงหนึ่งงานต่อ model ในเวลาเดียวกัน
- [ ] แสดงสถานะ download/success/failure โดย failure ไม่รบกวนการใช้งานโมเดลเดิม

**Verification:** manual test เปิดแอปแบบ online/offline และสลับหน้าอย่างรวดเร็ว

**Dependencies:** Task 5

**Files likely touched:**

- `lib/main.dart` หรือ controller ที่เป็นจุดเริ่มระบบโมเดล
- `lib/presentation/controllers/camera_inference_controller.dart`

**Estimated scope:** Small

## Checkpoint: หลัง Task 4-6

- [ ] `flutter analyze` ผ่าน
- [ ] `flutter test` ผ่าน
- [ ] build Android สำเร็จ
- [ ] อัปเดต Release แล้วแอปเดิมดาวน์โหลดโมเดลใหม่ได้
- [ ] ตัดอินเทอร์เน็ตแล้วแอปยังใช้โมเดลเดิมได้

## Task 7: จัดทำและทดสอบ GitHub Release จริง

**Description:** สร้าง checksum, manifest และ Release assets แล้วทดสอบ upgrade/rollback บนอุปกรณ์จริง

**Acceptance criteria:**

- [ ] URL `releases/latest/download/model_manifest.json` ดาวน์โหลด manifest ล่าสุดได้
- [ ] SHA-256 ใน manifest ตรงกับไฟล์ Release ทุกไฟล์
- [ ] ไม่แก้ asset ใน Release เดิม แต่สร้าง tag/version ใหม่ทุกครั้ง

**Verification:** ทดสอบติดตั้ง APK ที่มี bundled model เก่า แล้ว publish Release ใหม่โดยไม่ rebuild APK

**Dependencies:** Task 6

**Files likely touched:**

- `assets/config/model_manifest.example.json`
- Release assets บน GitHub

**Estimated scope:** Small

## ขั้นตอนการเผยแพร่โมเดลแต่ละเวอร์ชัน

1. Export โมเดลเป็นชื่อที่มีเวอร์ชัน
2. ทดสอบ input/output, class metadata ภายใน YOLO11 `.tflite` และ inference บนอุปกรณ์จริง
3. คำนวณ SHA-256 ด้วย `Get-FileHash <file> -Algorithm SHA256`
4. สร้าง `model_manifest.json` และใส่ URL, size, checksum จริง
5. สร้าง tag เช่น `model-v1.2.0`
6. สร้าง GitHub Release แบบ draft
7. upload manifest และ models ให้ครบ
8. ตรวจ URL และ checksum จากไฟล์ที่ดาวน์โหลดกลับจาก Release
9. publish Release
10. เปิดแอปเวอร์ชันเดิม ตรวจว่า download และ activate สำเร็จ

## Rollback

- อย่าลบ bundled model ออกจาก APK
- เก็บ downloaded model ก่อนหน้าอย่างน้อยหนึ่งรุ่น
- หาก inference initialization ล้มเหลว ให้ mark รุ่นใหม่ว่า failed และกลับไปรุ่นก่อนหน้า
- หากต้อง rollback ทั้งระบบ ให้สร้าง Release ใหม่ที่ manifest ชี้ไปยังโมเดล stable; ไม่แก้ Release/tag เดิม

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| checksum ถูกแก้พร้อมกับไฟล์บนบัญชี GitHub ที่ถูกยึด | High | จำกัด HTTPS/host, ใช้ immutable releases และเพิ่ม signature verification ในระยะถัดไป |
| ไฟล์ใหญ่ทำให้ RAM เต็ม | High | streaming download และ hash |
| แอปถูกปิดระหว่างดาวน์โหลด | Medium | `.part`, cleanup และ retry ครั้งถัดไป |
| โมเดลใหม่ output schema ไม่ตรงโค้ด | High | `minimumAppVersion`, metadata compatibility และโหลดทดสอบก่อน activate |
| private repository ต้องใช้ token | High | ใช้ backend/proxy; ห้ามฝัง token ใน mobile app |
| Release latest เลือก prerelease ผิดความตั้งใจ | Medium | ใช้ stable release เท่านั้นและทดสอบ URL ก่อน publish |

## Definition of Done

- [ ] แอปที่ติดตั้งแล้วอัปเดตโมเดลจาก Release ได้โดยไม่ rebuild APK
- [ ] checksum ผิดแล้วไม่ activate
- [ ] offline และ server error ยังใช้งาน bundled/previous model ได้
- [ ] rollback ทำงานจริงบนอุปกรณ์ Android
- [ ] tests, analyze และ Android build ผ่าน

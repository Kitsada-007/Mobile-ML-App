# Todo: GitHub Release Model Update

## Phase 1: Foundation

- [x] Task 1: สร้างและทดสอบ remote manifest contract
- [x] Task 2: สร้างและทดสอบ manifest HTTP client
- [x] Task 3: สร้าง streaming downloader, size guard และ SHA-256 verification

## Checkpoint 1

- [x] Parser/client/downloader tests ผ่าน
- [x] ไฟล์ไม่สมบูรณ์ไม่ถูก activate

## Phase 2: Activation

- [x] Task 4: สร้าง active-model registry และ semantic version comparison
- [x] Task 5: เชื่อม updater และ fallback/rollback เข้ากับ `ModelManager`
- [x] Task 6: เรียก background update โดยไม่ขวาง startup และป้องกันงานซ้ำ

## Checkpoint 2

- [x] `flutter analyze` ผ่าน
- [x] `flutter test` ผ่าน (44 tests)
- [x] Android build ผ่าน (`flutter build apk --debug --no-pub`)
- [ ] online/offline/failure flows ผ่าน

## Phase 3: Release

- [ ] Task 7: สร้าง Release draft พร้อม manifest และ models
- [ ] ตรวจ SHA-256 จากไฟล์ที่ดาวน์โหลดกลับจาก Release
- [ ] ทดสอบอัปเดตด้วย APK เดิมบนอุปกรณ์ Android
- [ ] ทดสอบ rollback ไป previous/bundled model

## Complete

- [ ] แอปอัปเดตโมเดลโดยไม่ rebuild APK ได้
- [ ] เอกสาร release procedure และ recovery procedure พร้อมใช้งาน

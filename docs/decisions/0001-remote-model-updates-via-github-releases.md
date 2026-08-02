# ADR-0001: อัปเดตโมเดลผ่าน GitHub Releases พร้อม Bundled Fallback

## Status

Accepted

## Date

2026-07-18

## Context

เดิมแอปโหลดโมเดลจาก `assets/models/` และคัดลอกไป application documents การเปลี่ยนโมเดลใน assets จึงต้อง build และแจก APK ใหม่

ต้องการให้แอปที่ติดตั้งแล้วรับโมเดลรุ่นใหม่ได้ โดยยังทำงานแบบ offline และย้อนกลับเมื่อไฟล์หรือโมเดลใหม่มีปัญหา

## Decision

ใช้ GitHub Release assets สำหรับเผยแพร่ `model_manifest.json` และโมเดล YOLO11 `.tflite` ซึ่งมี class metadata ฝังอยู่ภายใน แอปตรวจ latest stable Release แบบ background ดาวน์โหลดเป็นไฟล์ชั่วคราว ตรวจ size และ SHA-256 แล้ว activate แบบ atomic

เก็บ bundled models ไว้ใน APK เป็น fallback ตลอด และเก็บ downloaded model ก่อนหน้าอย่างน้อยหนึ่งรุ่นเพื่อ rollback

## Alternatives Considered

### เปลี่ยนไฟล์ใน assets แล้ว build APK ใหม่ทุกครั้ง

- ข้อดี: implementation ง่ายและทำงาน offline
- ข้อเสีย: ผู้ใช้ต้องอัปเดตแอปแม้เปลี่ยนเฉพาะ model weights
- ไม่เลือกเป็นวิธีหลัก เพราะไม่ตอบโจทย์ remote model update

### Commit โมเดลลง Git หรือ Git LFS

- ข้อดี: version model ผูกกับ source history
- ข้อเสีย: mobile app ยังต้องมี download/version activation flow และ Git repository ไม่ใช่ update API สำหรับแอป
- ใช้ Git LFS ได้สำหรับจัดเก็บ แต่ไม่ใช้เป็น runtime update contract

### ใช้ Firebase Storage หรือ object storage

- ข้อดี: access control, CDN และ staged rollout จัดการได้ดีกว่า
- ข้อเสีย: เพิ่ม infrastructure และ configuration
- พิจารณาในอนาคตเมื่อ private distribution, analytics หรือ staged rollout เป็น requirement

## Consequences

- เปลี่ยน model weights ได้โดยไม่ rebuild APK หาก input/output contract ยังรองรับแอปรุ่นเดิม
- แอปต้องเพิ่ม manifest validation, download, checksum, registry และ rollback logic
- public GitHub repository ดาวน์โหลดได้โดยไม่ฝัง secret
- SHA-256 เพียงอย่างเดียวไม่ยืนยันผู้เผยแพร่ หาก threat model สูงต้องเพิ่ม manifest signature
- โมเดลที่เปลี่ยน input/output contract ต้องเพิ่ม `minimumAppVersion` และอาจยังต้องออก APK ใหม่

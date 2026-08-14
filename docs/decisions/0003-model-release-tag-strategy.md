# ADR-0003: แยก tag ของ model release ออกจาก tag ของ APK release

## Status

Accepted

## Date

2026-08-15

## Context

ตาม ADR-0001 แอปตรวจหาโมเดลรุ่นใหม่จาก GitHub Releases โดยเดิมใช้ URL `releases/latest/download/model_manifest.json`

GitHub นิยาม `releases/latest` ว่าเป็น Release ล่าสุดของ repository โดยรวม ไม่ใช่ Release ล่าสุดที่มีโมเดล เมื่อ CI (`.github/workflows/release.yml`) publish APK release จาก tag `vX.Y.Z` release นั้นจะกลายเป็น latest ทันที และไม่มี `model_manifest.json` แนบอยู่

ผลคือการเช็คอัปเดตโมเดลได้ 404 และล้มเหลวแบบเงียบ ๆ แอปยังทำงานต่อได้ด้วย bundled fallback แต่จะไม่มีทางได้รับโมเดลรุ่นใหม่อีกเลยจนกว่าจะมี model release ใหม่ที่บังเอิญเป็น latest — ซึ่งเป็นภาวะที่ผู้ใช้และผู้พัฒนาไม่เห็นสัญญาณผิดปกติใด ๆ

## Decision

แยก tag ออกเป็นสองสายอย่างชัดเจน

- `vX.Y.Z` — APK release ที่ CI สร้าง ไม่เกี่ยวข้องกับ manifest ของโมเดล
- `model-vX.Y.Z` — model release ที่เก็บไฟล์ `.tflite` แบบ versioned ถาวร
- `model-latest` — tag คงที่ที่ชี้ไปยัง `model_manifest.json` ฉบับที่ใช้งานจริงในขณะนั้น

แอปเปลี่ยนไปอ่าน manifest จาก path ที่ระบุ tag ตรง ๆ

```
releases/download/model-latest/model_manifest.json
```

path นี้ไม่ขึ้นกับลำดับเวลาของ release ใด ๆ การ publish APK release จึงไม่กระทบการเช็คอัปเดตโมเดลอีกต่อไป

ตัว `model_manifest.json` ยังคงชี้ URL ของไฟล์ `.tflite` ไปยัง tag แบบ versioned (`model-vX.Y.Z`) เพื่อให้แต่ละรุ่นของโมเดลมีที่อยู่ถาวร ตรวจสอบย้อนหลังได้ และรองรับ rollback ตาม ADR-0001

## Alternatives Considered

### ให้ CI แนบ manifest ไปกับ APK release ทุกครั้ง

- ข้อดี: `releases/latest` ใช้ได้ต่อโดยไม่ต้องแก้โค้ดแอป และมี manifest อยู่ที่ release ล่าสุดเสมอ
- ข้อเสีย: ผูก lifecycle ของโมเดลเข้ากับ lifecycle ของ APK ซึ่ง ADR-0001 ตั้งใจแยกออกจากกันตั้งแต่แรก การออก APK ที่ไม่ได้แตะโมเดลเลยจะกลายเป็นการ re-publish manifest และหาก manifest ที่ CI แนบไม่ตรงกับโมเดลที่ปล่อยจริง จะเกิด version skew ที่ผู้ใช้ได้รับโมเดลผิดรุ่น
- ไม่เลือก เพราะเพิ่มความรับผิดชอบเรื่องโมเดลให้ APK pipeline โดยไม่ได้แก้ปัญหาที่ต้นเหตุ

### ใช้ GitHub API เพื่อค้นหา release ที่มี prefix `model-`

- ข้อดี: ไม่ต้องดูแล tag คงที่ และเลือก model release ล่าสุดได้อย่างถูกต้อง
- ข้อเสีย: ต้องเรียก REST API ซึ่งมี rate limit สำหรับ unauthenticated request และเพิ่ม parsing logic กับ failure mode ใหม่ในแอป
- ไม่เลือก เพราะ static asset URL เพียงพอกับความต้องการปัจจุบัน

## Consequences

- **ทุกครั้งที่ปล่อยโมเดลใหม่ ต้อง force-update tag `model-latest` ให้ชี้ manifest ฉบับใหม่** ขั้นตอนนี้เป็น manual step ที่ห้ามข้าม หากลืม แอปจะยังได้รับ manifest เก่าและไม่มีสัญญาณเตือน
- ต้องมี release ที่ tag `model-latest` อยู่จริงพร้อมไฟล์ `model_manifest.json` แนบ มิฉะนั้นการเช็คอัปเดตจะ 404 เหมือนปัญหาเดิม
- การ publish APK release ไม่กระทบการเช็คอัปเดตโมเดลอีกต่อไป
- ไฟล์ `.tflite` ยังอยู่ที่ tag แบบ versioned จึงตรวจสอบย้อนหลังและ rollback ได้ตาม ADR-0001
- ควรพิจารณาให้ CI ตรวจสอบว่า `model-latest` ชี้ manifest ที่ SHA-256 ตรงกับไฟล์จริง เพื่อลดความเสี่ยงจาก manual step นี้

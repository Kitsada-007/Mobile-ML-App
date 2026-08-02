# วิธีเพิ่มระบบอัปเดตโมเดลจาก GitHub Release แบบ Step by Step

คู่มือนี้ใช้กับ repository `Kitsada-007/Mobile-ML-App` และทำให้แอป Android ที่ติดตั้งแล้วสามารถดาวน์โหลดโมเดล `.tflite` รุ่นใหม่ได้โดยไม่ต้อง build APK ใหม่

โมเดลใน `assets/models/` จะยังอยู่ใน APK และเป็น fallback เมื่อออฟไลน์ ดาวน์โหลดล้มเหลว หรือโมเดลใหม่ใช้งานไม่ได้

## ภาพรวมการทำงาน

```text
เปิดแอป
  |
  +--> ใช้ downloaded model ที่ตรวจสอบแล้ว
  |       หรือ fallback ไป assets/models
  |
  +--> ตรวจ model_manifest.json จาก GitHub Release แบบ background
           |
           +--> เวอร์ชันเท่าเดิม: ไม่ทำอะไร
           |
           +--> เวอร์ชันใหม่: ดาวน์โหลดเป็น .part
                                  |
                                  +--> ตรวจ size + SHA-256
                                  |
                                  +--> ผ่าน: rename และ activate
                                  |
                                  +--> ไม่ผ่าน: ลบ .part และใช้รุ่นเดิม
```

## Step 0: ตรวจสิ่งที่โปรเจกต์มีอยู่แล้ว

dependencies ที่ต้องใช้มีอยู่ใน `pubspec.yaml` แล้ว:

```yaml
http: ^1.6.0
path_provider: ^2.1.5
shared_preferences: ^2.5.4
crypto: ^3.0.7
```

รัน:

```powershell
flutter pub get
```

> Direct download เหมาะกับ public repository หาก repository เป็น private ห้ามฝัง GitHub token ใน APK ให้ใช้ backend ที่ยืนยันตัวตนและส่งไฟล์แทน

## Step 1: เก็บ bundled model ไว้เป็น fallback

ให้มีโมเดลที่ใช้งานได้ใน:

```text
assets/models/best_float16New.tflite
assets/models/best_float16_number.tflite
```

แนะนำให้แก้ `pubspec.yaml` ให้รวมทั้ง directory:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/models/
    - assets/images/
    - assets/config/
    - assets/logo.png
    - assets/applogo.png
    - assets/iou.png
```

จากนั้นรัน:

```powershell
flutter pub get
```

ผลที่ต้องได้: แอปยังเปิด inference ด้วย bundled model ได้แม้ไม่มีอินเทอร์เน็ต

## Step 2: กำหนดรูปแบบ Remote Manifest

ในแต่ละ GitHub Release ต้องแนบไฟล์ชื่อคงที่:

```text
model_manifest.json
```

ตัวอย่างสำหรับ Release `model-v1.2.0`:

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
      "sha256": "ใส่ค่า SHA256 ตัวพิมพ์เล็ก 64 ตัว",
      "sizeBytes": 12345678
    },
    "number": {
      "version": "1.2.0",
      "fileName": "number_model_v1_2_0.tflite",
      "url": "https://github.com/Kitsada-007/Mobile-ML-App/releases/download/model-v1.2.0/number_model_v1_2_0.tflite",
      "sha256": "ใส่ค่า SHA256 ตัวพิมพ์เล็ก 64 ตัว",
      "sizeBytes": 12345678
    }
  }
}
```

URL ที่แอปใช้ตรวจรุ่นล่าสุด:

```text
https://github.com/Kitsada-007/Mobile-ML-App/releases/latest/download/model_manifest.json
```

ข้อกำหนด:

- `schemaVersion` ต้องเป็นค่าที่แอปรองรับ
- `version` ใช้รูปแบบ `major.minor.patch`
- `fileName` ต้องเป็นชื่อไฟล์อย่างเดียว ห้ามมี `/`, `\` หรือ `..`
- `url` ต้องเป็น HTTPS และชี้ไปยัง host ที่อนุญาต
- `sha256` ต้องเป็น hexadecimal 64 ตัว
- `sizeBytes` ต้องตรงกับขนาดไฟล์จริง
- `minimumAppVersion` ป้องกันโมเดลใหม่ที่ input/output ไม่รองรับแอปรุ่นเก่า

## Step 3: สร้าง Manifest Model และ Validation

สร้างไฟล์:

```text
lib/core/models/model_manifest.dart
```

ภายในควรมี type ดังนี้:

```dart
class ModelManifest {
  final int schemaVersion;
  final String releaseVersion;
  final String minimumAppVersion;
  final Map<String, RemoteModelInfo> models;

  const ModelManifest({
    required this.schemaVersion,
    required this.releaseVersion,
    required this.minimumAppVersion,
    required this.models,
  });

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    // Parse และ validate ทุก field ก่อนคืนค่า
    throw UnimplementedError();
  }
}

class RemoteModelInfo {
  final String version;
  final String fileName;
  final Uri url;
  final String sha256;
  final int sizeBytes;

  const RemoteModelInfo({
    required this.version,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.sizeBytes,
  });
}
```

Validation ที่ต้องเขียน:

1. `schemaVersion == 1`
2. version ต้องเป็นตัวเลขสามส่วน เช่น `1.2.0`
3. `url.scheme == 'https'`
4. host ต้องเป็น `github.com` หรือ host ที่ระบบอนุญาต
5. `fileName` ต้องลงท้าย `.tflite`
6. ปฏิเสธชื่อที่มี path separator หรือ `..`
7. SHA-256 ต้องตรงกับ RegExp `^[a-f0-9]{64}$`
8. `sizeBytes` ต้องมากกว่า 0 และไม่เกินขนาดสูงสุดที่แอปกำหนด

สร้าง test:

```text
test/core/models/model_manifest_test.dart
```

ทดสอบ manifest ที่ถูกต้อง, field หาย, URL เป็น HTTP, SHA ผิด และ filename แบบ path traversal

## Step 4: สร้าง Client สำหรับอ่าน Manifest ล่าสุด

สร้างไฟล์:

```text
lib/services/model_update_client.dart
```

หน้าที่ของ service:

1. รับ `http.Client` ผ่าน constructor เพื่อให้ test ได้
2. GET latest manifest URL
3. กำหนด timeout เช่น 15 วินาที
4. ยอมรับเฉพาะ HTTP 200
5. จำกัดขนาด manifest เช่นไม่เกิน 256 KB
6. decode JSON
7. ส่ง JSON เข้า `ModelManifest.fromJson()`
8. เมื่อ offline/timeout/JSON เสีย ให้คืนผลลัพธ์แบบ failure โดยไม่ทำให้แอป crash

โครงสร้าง API ที่แนะนำ:

```dart
class ModelUpdateClient {
  ModelUpdateClient(this._client, {required this.manifestUri});

  final http.Client _client;
  final Uri manifestUri;

  Future<ModelManifest> fetchLatestManifest() async {
    // GET, timeout, size guard, JSON decode และ validation
    throw UnimplementedError();
  }
}
```

## Step 5: สร้าง File Store และ Download Model

สร้างไฟล์:

```text
lib/services/model_file_store.dart
```

ตำแหน่งจัดเก็บที่แนะนำ:

```text
<application-documents>/models/traffic/1.2.0/traffic_model_v1_2_0.tflite
<application-documents>/models/number/1.2.0/number_model_v1_2_0.tflite
```

ลำดับการดาวน์โหลด:

1. สร้าง directory ของ model id และ version
2. download ลง `<fileName>.part`
3. ใช้ `http.Client.send()` เพื่อรับข้อมูลแบบ stream
4. เขียน stream ลง disk โดยไม่โหลดทั้งโมเดลเข้า RAM
5. ตรวจจำนวน byte กับ `sizeBytes`
6. อ่านไฟล์ `.part` แบบ stream เพื่อคำนวณ SHA-256
7. เปรียบเทียบ digest แบบ lowercase
8. ถ้าไม่ตรง ให้ลบ `.part`
9. ถ้าตรง ให้ rename `.part` เป็น `.tflite`
10. คืน final path

ตัวอย่างการ hash แบบไม่โหลดทั้งไฟล์เข้า RAM:

```dart
final digest = await sha256.bind(tempFile.openRead()).first;
final actualSha256 = digest.toString().toLowerCase();
```

กฎสำคัญ:

- ห้ามเขียนทับ active model โดยตรง
- ห้าม activate `.part`
- ปิด file sink ใน `finally`
- ลบ `.part` เมื่อ timeout, cancel, checksum ผิด หรือ disk เต็ม
- จำกัดขนาดโมเดลสูงสุด เช่น 500 MB เพื่อป้องกันไฟล์ผิดปกติ

## Step 6: สร้าง Registry สำหรับ Active Model

สร้างไฟล์:

```text
lib/services/model_registry.dart
```

เก็บข้อมูลแยกตาม model id ด้วย `SharedPreferences`:

```text
model.traffic.version
model.traffic.path
model.traffic.sha256
model.number.version
model.number.path
model.number.sha256
```

Registry ต้องมีความสามารถ:

- อ่าน active version/path
- ตรวจว่าไฟล์ยังมีอยู่จริง
- activate รุ่นใหม่หลัง download และ checksum ผ่านแล้วเท่านั้น
- เก็บ previous version/path สำหรับ rollback
- clear active record ที่เสียหาย

อย่าเปรียบเทียบ version ด้วย string โดยตรง เพราะ `1.10.0` ต้องใหม่กว่า `1.9.0` ให้แยก major/minor/patch เป็นตัวเลขก่อนเปรียบเทียบ

## Step 7: สร้าง Model Updater

สร้างไฟล์:

```text
lib/services/model_updater.dart
```

flow ของ `checkForUpdates()`:

```text
fetch manifest
    |
validate minimumAppVersion
    |
วน traffic และ number
    |
อ่าน active version
    |
remote ใหม่กว่า?
    +-- ไม่: ข้าม
    +-- ใช่: download -> size -> SHA-256 -> activate
```

API ที่แนะนำ:

```dart
enum ModelUpdateStatus {
  checking,
  downloading,
  updated,
  alreadyCurrent,
  failed,
}

class ModelUpdater {
  Future<void> checkForUpdates() async {
    // Orchestrate client, file store และ registry
  }
}
```

เพิ่ม lock หรือเก็บ `Future` ที่กำลังทำงาน เพื่อป้องกันหลายหน้าจอเรียกดาวน์โหลดโมเดลเดียวกันพร้อมกัน

## Step 8: แก้ ModelManager ให้เลือกโมเดลตามลำดับ

แก้ไฟล์:

```text
lib/services/model_manager.dart
```

ก่อนตรวจ Native Channel หรือ copy asset ให้ทำ:

1. แปลง `ModelType` เป็น model id เช่น `traffic` หรือ `number`
2. ขอ active path จาก `ModelRegistry`
3. ถ้า path มีอยู่และผ่านการตรวจสอบ ให้คืน downloaded path
4. ถ้าไม่มี ให้ทำ flow bundled asset เดิม

ลำดับสุดท้าย:

```dart
Future<String?> getModelPath(ModelType modelType) async {
  final downloadedPath = await registry.resolveActivePath(modelType.id);
  if (downloadedPath != null) {
    return downloadedPath;
  }

  return _getBundledModelPath(modelType);
}
```

ควรเพิ่ม `id` และ bundled path ใน `ModelType`:

```dart
enum ModelType {
  traffic(
    'traffic',
    'assets/models/best_float16New.tflite',
    YOLOTask.detect,
  ),
  number(
    'number',
    'assets/models/best_float16_number.tflite',
    YOLOTask.detect,
  );

  final String id;
  final String bundledAssetPath;
  final YOLOTask task;

  const ModelType(this.id, this.bundledAssetPath, this.task);
}
```

## Step 9: เรียก Update แบบ Background

แอปต้องเปิดด้วย local model ก่อน ไม่ควรให้ผู้ใช้รอ network ที่หน้าเริ่มต้น

ลำดับที่แนะนำ:

1. เริ่มแอป
2. โหลด downloaded/bundled model ที่มีอยู่
3. แสดง UI และเปิด inference ตามปกติ
4. เรียก `ModelUpdater.checkForUpdates()` แบบ background หนึ่งครั้งต่อ session
5. หากมีรุ่นใหม่ ให้แจ้งว่าโมเดลพร้อมใช้งาน
6. ใช้รุ่นใหม่เมื่อสร้าง inference session ครั้งถัดไป หรือขอให้ผู้ใช้ restart inference

อย่าสลับไฟล์ใต้ inference session ที่กำลังทำงาน เพราะ native runtime อาจกำลังอ่านไฟล์นั้นอยู่

## Step 10: โหลดทดสอบและ Rollback

SHA-256 บอกว่าไฟล์ดาวน์โหลดครบ แต่ไม่ได้ยืนยันว่าโมเดลเข้ากับโค้ด inference

ก่อนยืนยัน active model:

1. ตรวจ input shape
2. ตรวจ output shape
3. ตรวจ class metadata ที่ฝังอยู่ภายใน YOLO11 `.tflite`
4. ทดลอง initialize interpreter/model
5. ถ้า initialize สำเร็จ จึง commit active record
6. ถ้าล้มเหลว ให้ mark รุ่นนั้นว่า failed และกลับ previous/bundled model

เก็บโมเดลก่อนหน้าอย่างน้อยหนึ่งเวอร์ชัน และลบเฉพาะเวอร์ชันที่เก่ากว่านั้นหลังรุ่นใหม่ทำงานสำเร็จแล้ว

## Step 11: เตรียมไฟล์สำหรับ GitHub Release

ตัวอย่างไฟล์รุ่น `1.2.0`:

```text
release-model-v1.2.0/
  model_manifest.json
  traffic_model_v1_2_0.tflite
  number_model_v1_2_0.tflite
```

คำนวณขนาดและ SHA-256:

```powershell
Get-Item .\traffic_model_v1_2_0.tflite | Select-Object Name, Length
Get-FileHash .\traffic_model_v1_2_0.tflite -Algorithm SHA256

Get-Item .\number_model_v1_2_0.tflite | Select-Object Name, Length
Get-FileHash .\number_model_v1_2_0.tflite -Algorithm SHA256
```

นำ `Length` ไปใส่ `sizeBytes` และแปลง hash เป็นตัวพิมพ์เล็กก่อนใส่ `sha256`

## Step 12: สร้าง Tag และ GitHub Release

commit โค้ด/metadata ที่เกี่ยวข้องก่อน:

```powershell
git add .
git commit -m "feat(model): prepare model v1.2.0"
git push origin main
```

สร้าง tag:

```powershell
git tag -a model-v1.2.0 -m "Model version 1.2.0"
git push origin model-v1.2.0
```

สร้าง Release ด้วย GitHub CLI:

```powershell
gh release create model-v1.2.0 `
  .\model_manifest.json `
  .\traffic_model_v1_2_0.tflite `
  .\number_model_v1_2_0.tflite `
  --repo Kitsada-007/Mobile-ML-App `
  --title "Model v1.2.0" `
  --notes "Update traffic and number detection models"
```

แนะนำให้สร้างเป็น draft ก่อน ตรวจ assets ให้ครบแล้วจึง publish อย่าแก้ไข Release เดิมหลังเผยแพร่ ให้สร้าง version/tag ใหม่เสมอ

## Step 13: ทดสอบ End-to-End

### กรณีอัปเดตสำเร็จ

1. ติดตั้ง APK ที่ bundled model เป็นรุ่นเก่า
2. เปิดแอปและยืนยันว่า inference ทำงาน
3. publish GitHub Release รุ่นใหม่
4. ปิดและเปิดแอป หรือกดตรวจอัปเดต
5. ตรวจว่า `.part` ถูกสร้างระหว่างดาวน์โหลด
6. ตรวจว่า active version เปลี่ยนหลัง checksum ผ่าน
7. เริ่ม inference session ใหม่
8. ยืนยันว่าใช้ model path รุ่นใหม่

### กรณีต้องผ่านทั้งหมด

- ไม่มีอินเทอร์เน็ต: ใช้ local model ได้
- HTTP 404/500: ไม่ crash
- manifest JSON เสีย: ไม่ดาวน์โหลด
- SHA-256 ผิด: ลบ `.part` และใช้รุ่นเดิม
- ดาวน์โหลดขาดช่วง: retry ครั้งหน้าได้
- disk เต็ม: แจ้ง failure และใช้รุ่นเดิม
- minimum app version สูงกว่าแอป: ไม่ activate
- โมเดล initialize ไม่สำเร็จ: rollback

รัน quality checks:

```powershell
flutter analyze
flutter test
flutter build apk --release
```

## Step 14: วิธี Rollback Release

อย่าแก้ tag หรือ asset ของ Release ที่เผยแพร่แล้ว

ให้สร้าง Release ใหม่ เช่น `model-v1.2.1` โดย manifest ชี้กลับไปยังโมเดล stable หรือแนบไฟล์ stable ภายใต้ชื่อรุ่นใหม่:

```text
model-v1.2.0  -> โมเดลมีปัญหา
model-v1.2.1  -> นำโมเดล stable กลับมาเผยแพร่
```

แอปจะเห็น `1.2.1` ใหม่กว่า `1.2.0` และเปลี่ยนกลับไปใช้โมเดล stable ตาม flow ปกติ

## ข้อควรระวังด้านความปลอดภัย

- SHA-256 ตรวจความสมบูรณ์ของไฟล์ แต่ถ้าผู้โจมตีแก้ได้ทั้งโมเดลและ manifest ก็ไม่สามารถยืนยันผู้เผยแพร่ได้
- ระบบที่มีความเสี่ยงสูงควรเซ็น manifest ด้วย private key และฝัง public key สำหรับตรวจ signature ในแอป
- จำกัด HTTPS host, ขนาดไฟล์, timeout และจำนวน redirect
- ห้ามใช้ filename จาก server สร้าง path โดยไม่ validate
- ห้ามฝัง GitHub Personal Access Token ใน mobile application

## เอกสารที่เกี่ยวข้อง

- [แผนงานและ acceptance criteria](../tasks/plan.md)
- [รายการงาน](../tasks/todo.md)
- [GitHub: Managing releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)
- [GitHub: About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)

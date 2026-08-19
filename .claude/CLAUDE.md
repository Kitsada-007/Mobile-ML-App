# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# traffic_light_app (Mobile-ML-App)

Flutter app that detects Thai traffic-light signals and countdown timers on-device with YOLO11,
across three input modes (live camera / still image / video file), and speaks Thai TTS alerts.

Derived from Ultralytics' [yolo-flutter-app](https://github.com/ultralytics/yolo-flutter-app)
(AGPL-3.0) — derived code must keep the original license header, and code from
license-incompatible repositories must not be added.

Package name is `trffic_ilght_app` (typo is baked into every import path — do not "fix" it).
Source comments and all user-facing strings are Thai; keep new code consistent with that.

## Commands

- `flutter analyze` — static analysis (required before commit)
- `flutter build apk --debug --no-pub` — required after touching native or model wiring

CI workflows pin Flutter 3.44.6 stable — match that locally when a failure looks version-dependent.

## Tech stack

- State: `provider` only. `get` is in `pubspec.yaml` but its reactive state is unused — don't start using it.

## Architecture

Feature-first (ADR-0002): `lib/features/<feature>/{data,presentation}`. Cross-feature logic lives
in `lib/core/services/` only. Tests mirror the same structure under `test/`.

**Do not create empty layers.** Add `data/`, `repositories/`, etc. only when real code goes in
them; never scaffold for symmetry. `image_detection` has only `presentation/` on purpose.

For ML/voice/model changes used by more than one feature, edit the existing service in
`core/services/` — do not introduce a new top-level singleton.

Composition root is `lib/main.dart`: it installs `SettingsProvider` and fires
`RemoteModelUpdateBootstrap.checkOnce()` fire-and-forget. Routes are plain
`MaterialPageRoute` factories in `lib/app/routes.dart`.

## Three features, three different pipelines

The three features share `core/services` primitives but wire them differently. Reading one
controller does **not** tell you how the others behave.

**Camera (`camera_inference_controller.dart`, ~900 lines) — the most complex path.**
Native YOLOView stream → `LatestFrameQueue` (keeps newest packet, drops the rest) →
`RealtimeFrameFreshnessGuard` (rejects stale/out-of-order frames; a 200 ms watchdog timer calls
`expireStaleResults` to blank the UI when frames stop) → `DetectionStabilizer.update` →
`VoiceAlertController` → `TrafficVoiceService`. In parallel, `RealtimeNumberInferenceEngine`
(throttled to 400 ms) drives the sign-number path and owns its own `CountdownReadingStabilizer`.
Camera does **not** use `SignalInterpreter` or `CountdownAlertController`.

**Video (`video_inference_controller.dart`).** FFmpeg frame extraction →
`VideoFrameAnalysisService` → `DetectionStabilizer.update` → both `SignalInterpreter.interpret`
(produces the `DriverSignalResult` banner) and `CountdownAlertController.update` (produces the
countdown UI string plus a threshold voice event) → `VoiceAlertController` → `TrafficVoiceService`.
`SignalInterpreter` and `CountdownAlertController` are used **only here**.

**Image (`single_image_screen.dart`).** One-shot: `parseYoloDetections` on the platform-channel
result, then `SignNumberPipelineService.analyzeSingleImage`, which crops on a background isolate
via `compute()`. No stabilizer, no voice.

### Sign-number sub-pipeline (shared)

`sign_number` ROI → `SignNumberPipelineService` → `NumberDetectionService` (digit model,
confidence 0.25 / IoU 0.45, `readDigitSequence` with `maxDigits: 2`) → `CountdownReadingStabilizer`.
The pipeline crops twice — tight and wide — and prefers whichever yields more digits, breaking
ties on average confidence; realtime additionally retries with a rotated crop when frame rotation
is unknown. Realtime crops run on a reused isolate (`PersistentSignCropWorker`); single images use
`compute()`.

`sign_number` never enters the voting/voice path. It is in `roiOnlyClasses`, so
`participatesInStableDetection` and `participatesInVoiceAlerts` both return false for it — it
exists purely to locate the crop region (see `signClasses` vs `roiOnlyClasses` in
`detection_alert_config.dart`).

## Safety rules — do not change without walking the whole path

These are not general tuning knobs. Do not loosen them to "make it react faster".

- **Red light ⇒ `SignalAction.stop`, always.** All directional labels are dropped
  (`signal_interpreter.dart:_buildMessage`). Never add a branch that makes red produce `go`.
- **Only countdown values 1–5 become speech** ("เตรียมออกตัว") while red is showing. Anything
  outside that range falls back to "ไฟแดง - หยุดรอ". `CountdownReadingStabilizer` independently
  rejects readings outside 0–99.
- **`off_light` needs 12 consecutive frames OR 6 s of continuous presence**
  (`offLightMinimumFrames` / `offLightMinimumDuration`, applied as an **OR** in
  `_passesContinuousConfirmation`), versus 4-of-5 frames for every other light. The high bar keeps
  a normally blinking light from being reported as a malfunctioning one. Lowering it reintroduces
  that false positive.
- **`VoiceAlertController` speaks at most one message at a time.** `_isSpeaking` blocks overlap;
  candidates are chosen by `priority` (lower number = more important, see
  `DetectionAlertConfig._priorityFor`) then by per-class `voiceCooldown`. Do not add a parallel
  speaking path — route new speech through `speakMessageIfIdle`.
- **`CountdownReadingStabilizer` is deliberately asymmetric.** A step down of 0 or 1 is accepted
  immediately (latency matters in realtime); a value that *increases* needs `requiredMatches + 2`
  votes, and a drop larger than `maximumStepDown` needs `requiredMatches + 1`. Keep the asymmetry.
- **`parseYoloDetections` discards only malformed entries, never the whole frame.** Platform-channel
  data is untrusted: fields are type-checked before `YOLOResult.fromMap`, and a throw on one entry
  must not lose the valid detections beside it.

## Model classes and Thai labels

Class list lives in `assets/models/labels.txt`.

- Scope sections 3.10 (broken light) and 3.11 (blinking light) are collapsed into the single
  `off_light` class. There is no separate blinking-light class.
- `dont_go_straight_arrow` exists in the model and the code but is not yet written into the scope
  document (open item, `tasks/todo.md`).

There are **three intentionally different Thai string sets** for the same class names. Changing one
does not mean changing the others:

| Source | Purpose | Example for `green_light_circle` |
| --- | --- | --- |
| `signal_interpreter.dart:thaiLabel` | driver-facing phrasing inside `DriverSignalResult` | `ไฟเขียว` |
| `traffic_voice_service.dart:getThaiMessage` | spoken TTS alert (returns `""` when a class has no alert) | `ไฟเขียว ไปได้` |
| `traffic_detection_label_formatter.dart:videoFormalThaiName` | formal UI/report name | `สัญญาณไฟจราจรสีเขียว` |

## Model updates (ADR-0001, ADR-0003, `docs/remote-model-update-guide.md`)

The `.tflite` files bundled in `assets/models/` are the offline fallback. On startup (Android only,
once per session, non-blocking) the app fetches `model_manifest.json` from GitHub Releases.

- **The manifest URL is pinned to the `model-latest` tag**, not `releases/latest` (ADR-0003).
  `releases/latest` means "newest release in the repo", which an APK release silently hijacks,
  breaking model updates with a 404 that nobody sees. Publishing a new model therefore requires a
  manual force-update of the `model-latest` tag — an easy step to forget, with no alerting.
- **Verify size *and* SHA-256 before activating.** `model_file_store.dart` checks `contentLength`
  up front, aborts mid-download if the size is exceeded, and re-compares the digest afterwards.
  Neither check is optional.
- `ModelRegistry` keeps exactly two slots per `modelId`: `active` and `previous`. `previous` is the
  only rollback that exists — once overwritten there is no way back.
- `reportModelLoadFailure` marks the version failed and promotes `previous` into `active`. All
  three feature entry points (camera, video, image) must call it when YOLO fails to load — they do
  today; keep it that way when adding a fourth.
- The manifest requires **both** the `traffic` and `number` keys and a `schemaVersion` the app
  supports; a missing one is a `FormatException`, not a partial update.
- A model that changes the input/output contract must bump `minimumAppVersion` in the manifest and
  will likely still need an APK release.

## Conventions

- Don't hand-check style that `flutter_lints` already enforces — run `flutter analyze`.
- Controllers take `@visibleForTesting` constructor parameters (fake services, injectable `clock`,
  `enableFreshnessWatchdog: false`) instead of exposing setters. Follow that pattern for new
  time- or platform-dependent code so tests stay deterministic.
</content>
</invoke>


# CLAUDE.md

แนวทางการเขียนโค้ดสำหรับโปรเจกต์นี้ (`trffic_ilght_app`)
Claude Code ต้องอ่านและทำตามไฟล์นี้ทุกครั้งก่อนแก้โค้ด

---

## กฎสไตล์การเขียน (บังคับ)

โปรเจกต์นี้เน้น **โค้ดที่อ่านง่ายสำหรับคนที่เพิ่งเริ่ม Dart** มากกว่าโค้ดสั้น
ห้ามใช้ไวยากรณ์ย่อที่ต้องรู้ Dart ลึกถึงจะอ่านออก

### 1. ห้ามใช้ `??` (null-coalescing operator)

ให้เขียนเป็น `if / else` ธรรมดาแทน เพื่อให้เห็นเงื่อนไขชัด ๆ

```dart
// ❌ ห้าม
_picker = picker ?? ImagePicker();
final number = int.tryParse(text) ?? 0;

// ✅ ถูกต้อง
if (picker == null) {
  _picker = ImagePicker();
} else {
  _picker = picker;
}

int number;
final parsed = int.tryParse(text);
if (parsed == null) {
  number = 0;
} else {
  number = parsed;
}
```

ห้ามใช้ `??=` ด้วยเช่นกัน ให้เขียนเป็น `if (x == null) { x = ...; }`

### 2. ห้ามใช้ initializer list (`:` หลังวงเล็บ constructor)

ให้ย้ายการกำหนดค่าทั้งหมดเข้าไปใน body ของ constructor

```dart
// ❌ ห้าม
class Foo {
  Foo({ImagePicker? picker})
    : _picker = picker ?? ImagePicker(),
      _validator = const VideoInputValidator();

  final ImagePicker _picker;
  final VideoInputValidator _validator;
}

// ✅ ถูกต้อง
class Foo {
  Foo({ImagePicker? picker}) {
    if (picker == null) {
      _picker = ImagePicker();
    } else {
      _picker = picker;
    }
    _validator = const VideoInputValidator();
  }

  late final ImagePicker _picker;
  late final VideoInputValidator _validator;
}
```

**ข้อบังคับที่ตามมา:** field ที่เคยเป็น `final` ต้องเปลี่ยนเป็น `late final`
เพราะ Dart ไม่ยอมให้กำหนดค่า `final` ใน body — ดูหัวข้อ "ข้อควรรู้" ด้านล่าง

**ยกเว้น:** `this.ชื่อฟิลด์` ในพารามิเตอร์ constructor **ยังใช้ได้ปกติ**
เพราะไม่ใช่ initializer list และไม่มีเครื่องหมาย `:`

```dart
// ✅ ใช้ได้ ไม่ต้องแก้
VideoInferenceController({this.targetChecksPerSecond = 4});
```

### 3. ห้ามใช้ ternary operator (`? :`)

ให้เขียนเป็น `if / else` เต็มรูปแบบ

```dart
// ❌ ห้าม
return priorityOrder != 0
    ? priorityOrder
    : second.confidence.compareTo(first.confidence);

// ✅ ถูกต้อง
if (priorityOrder != 0) {
  return priorityOrder;
}
return second.confidence.compareTo(first.confidence);
```

ถ้าเป็นการกำหนดค่าตัวแปร ให้ประกาศตัวแปรก่อนแล้วกำหนดค่าใน `if / else`

```dart
// ❌ ห้าม
final transition = animationsDisabled
    ? Duration.zero
    : const Duration(milliseconds: 200);

// ✅ ถูกต้อง
Duration transition;
if (animationsDisabled) {
  transition = Duration.zero;
} else {
  transition = const Duration(milliseconds: 200);
}
```

### 4. ห้ามใช้ cascade operator (`..`)

ให้แยกเป็นคำสั่งทีละบรรทัด โดยเก็บวัตถุไว้ในตัวแปรก่อน

```dart
// ❌ ห้าม
final stableDetections = List<StableDetection>.from(update.stableDetections)
  ..sort((first, second) {
    final priorityOrder = _detectionConfig
        .ruleFor(first.className)
        .priority
        .compareTo(_detectionConfig.ruleFor(second.className).priority);
    return priorityOrder != 0
        ? priorityOrder
        : second.confidence.compareTo(first.confidence);
  });

// ✅ ถูกต้อง
final stableDetections = List<StableDetection>.from(update.stableDetections);
stableDetections.sort((first, second) {
  final firstPriority = _detectionConfig.ruleFor(first.className).priority;
  final secondPriority = _detectionConfig.ruleFor(second.className).priority;
  final priorityOrder = firstPriority.compareTo(secondPriority);
  if (priorityOrder != 0) {
    return priorityOrder;
  }
  return second.confidence.compareTo(first.confidence);
});
```

สังเกตว่านอกจากตัด `..` กับ `? :` แล้ว ยัง**แตกการต่อ method ยาว ๆ ออกเป็น
ตัวแปรที่มีชื่อ** (`firstPriority`, `secondPriority`) ซึ่งอ่านง่ายกว่าการไล่
`.ruleFor().priority.compareTo()` ติดกันสี่ชั้นมาก — ให้ทำแบบนี้ด้วยเสมอ

### 5. ใช้ `try / catch` เมื่อโค้ดอาจโยน exception

ทุกจุดที่แตะไฟล์ กล้อง โมเดล เครือข่าย หรือ plugin ต้องมี `try / catch`
และต้อง log ให้รู้ว่าพังตรงไหน ห้าม `catch` แล้วเงียบ

```dart
// ✅ ถูกต้อง
try {
  await _modelManager.loadModel();
} catch (error, stackTrace) {
  log('โหลดโมเดลไม่สำเร็จ: $error', stackTrace: stackTrace);
  _errorMessage = 'โหลดโมเดลไม่สำเร็จ กรุณาลองใหม่';
  notifyListeners();
}

// ❌ ห้าม — กลืน error เงียบ ๆ
try {
  await _modelManager.loadModel();
} catch (_) {}
```

ถ้าต้องคืนทรัพยากรไม่ว่าจะสำเร็จหรือพัง ให้ใช้ `finally`

```dart
try {
  await _processFrames();
} catch (error, stackTrace) {
  log('ประมวลผลเฟรมล้มเหลว: $error', stackTrace: stackTrace);
} finally {
  await _cleanupTempFolder();
}
```

**สำคัญ:** `try / catch` มีไว้จับ **exception** ไม่ใช่ใช้แทนการเช็ค `null`
ค่า null ที่คาดไว้อยู่แล้ว (เช่น `int.tryParse` คืน null) ต้องเช็คด้วย `if` เสมอ

```dart
// ❌ ผิดวัตถุประสงค์ — null ไม่ใช่ exception
try {
  final number = int.parse(text);
} catch (_) {
  number = 0;
}

// ✅ ถูกต้อง
final parsed = int.tryParse(text);
if (parsed == null) {
  number = 0;
} else {
  number = parsed;
}
```

---

## ข้อควรรู้ก่อนแก้ (อ่านให้จบ)

กฎข้อ 2 มีผลข้างเคียงที่ต้องยอมรับ:

`final` field ใน Dart **ต้อง** มีค่าตั้งแต่ตอนสร้างวัตถุ กำหนดได้แค่ 3 ที่:
ตอนประกาศ, ใน initializer list, หรือผ่าน `this.x` ในพารามิเตอร์
พอห้าม initializer list แล้ว field ที่ต้องคำนวณค่าจึงเหลือทางเดียวคือ `late final`

`late final` ต่างจาก `final` ตรงที่คอมไพเลอร์**ไม่ตรวจให้แล้ว**ว่ามีการกำหนดค่าครบ
ถ้าลืมกำหนดสักตัว จะไม่ error ตอน compile แต่จะพังตอนรันด้วย
`LateInitializationError` ซึ่งหาต้นตอยากกว่ามาก

ดังนั้นเวลาแก้ constructor ให้เป็นสไตล์นี้ **ต้องไล่ให้ครบทุก field**
และรัน `flutter test` ทุกครั้งหลังแก้ constructor

---

## ขอบเขตการแก้

โค้ดเดิมบางส่วนยังไม่ได้ใช้สไตล์นี้ (นับยอดคงเหลือได้ด้วย grep)

**อย่าแก้ทั้งหมดรวดเดียว** ให้แก้เฉพาะไฟล์ที่กำลังทำงานอยู่ในงานนั้น ๆ
แล้ว commit แยกด้วยข้อความ `style: <ชื่อไฟล์> ตามกฎใน CLAUDE.md`

โค้ดที่ยังไม่ได้แตะ ปล่อยไว้ก่อนได้ ไม่ถือว่าผิด

---

## กฎเดิมของโปรเจกต์ที่ยังต้องทำตาม

- คอมเมนต์อธิบาย **เหตุผล** เป็นภาษาไทย (อธิบายว่าทำไม ไม่ใช่ทำอะไร)
- โครงสร้างเทสต์ mirror ตาม `lib/` ทุกไฟล์
- `flutter analyze` ต้องไม่มี warning ใหม่
- `flutter test` ต้องผ่านทั้งหมดก่อน commit
- ห้ามแตะ lifecycle ของกล้อง (`_syncCameraLifecycle`, `_rebuildKey`,
  `didChangeDependencies`) โดยไม่จำเป็น — เปราะและเคยแก้มาแล้ว
- ห้ามเพิ่มคลาสสังเคราะห์ที่ไม่มีในโมเดล ห้ามแก้ `labels.txt` หรือ manifest
- `off_light` ต้องยืนยันยาก (ไฟจราจรปกติที่กล้องเห็นกะพริบจาก rolling
  shutter/PWM ต้องไม่ถูกรายงานว่าไฟเสีย) ห้ามลดความเข้มงวดของ flicker gate
  ใน `DetectionStabilizer`

---

## หมายเหตุ: บังคับอัตโนมัติไม่ได้

Dart analyzer **ไม่มี lint rule** สำหรับห้าม `??`, ternary, cascade หรือ
initializer list กฎในไฟล์นี้จึงบังคับใช้ด้วยการรีวิวเท่านั้น
เพิ่มใน `analysis_options.yaml` ไม่ได้

ถ้าต้องการให้ตรวจอัตโนมัติจริง ๆ ทางเดียวคือเขียน custom lint
(package `custom_lint`) ซึ่งยังไม่ได้ทำในโปรเจกต์นี้
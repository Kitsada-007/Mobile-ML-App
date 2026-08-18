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

CI (`.github/workflows/ci.yml`) runs `flutter analyze` + `flutter test` on every push and PR.
`.github/workflows/release.yml` fires only on a `vX.Y.Z` tag: it runs tests, builds a signed
release APK, and publishes it to GitHub Releases with `SHA256SUMS.txt`. Both workflows pin
Flutter 3.44.6 stable — match that locally when a failure looks version-dependent.

## Tech stack

- State: `provider` only. `get` is in `pubspec.yaml` but its reactive state is unused — don't start using it.
- ML: `ultralytics_yolo` 0.6.10 (pinned), YOLO11 `.tflite`

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

11 classes: `turn_left`, `turn_right`, `go_straight_arrow`, `dont_turn_left`, `dont_turn_right`,
`dont_go_straight_arrow`, `red_light_circle`, `yellow_light`, `green_light_circle`, `sign_number`,
`off_light`.

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

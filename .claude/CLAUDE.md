# traffic_light_app (Mobile-ML-App)

Flutter app detects Thai traffic light signals and countdown timers using YOLO11 on the device.
(Camera/Image/Video) with TTS audio alerts.
Adapted from Ultralytics' yolo-flutter-app (AGPL-3.0) — derived code must retain the original license header and do not include code from incompatible repositories.

## Commands

- Install deps: `flutter pub get`
- Static analysis (required before commit): `flutter analyze`
- All tests: `flutter test`
- Single file test: `flutter test test/path/to/file_test.dart`
- Build and check after modifications to native/model: `flutter build apk --debug --no-pub`

CI (`.github/workflows/release.yml`) runs only when pushing the `vX.Y.Z` tag. Run
`flutter test`, then build the APK and release it to Releases. There's no CI on PRs or regular pushes.
Therefore, `flutter analyze` + `flutter test` on the machine is the only stage.
The Flutter version used for CI is 3.44.6 stable.

## Tech stack

- Flutter/Dart SDK `^3.10.4`
- State: `provider` only (`get` is in deps but doesn't use its reactive state)
- ML: `ultralytics_yolo` (YOLO11 `.tflite`)
- Others: `camera`, `image_picker`, `video_player`, `image`,
`ffmpeg_kit_flutter_new`, `flutter_tts`, `shared_preferences`,
`path_provider`, `crypto`, `package_info_plus`

## Architecture

Feature-first approach ADR-0002: `lib/features/<feature>/{data,presentation}`
Cross-feature logic must be in `lib/core/services/` only. Mirror tests of the same structure are under `test/`.

**ADR-0002 Rule: Do not create empty layers.** — Add `data/`, `repositories/`.
Only include these when there is actual code; do not scaffold for symmetry.

Modify ML/voice/model logic. For cross-feature usage, modify the existing service in `core/services/`.
Do not create a new top-level singleton.

## Data Path — Two Parallel Paths

Path A (Traffic Signals/Signs):
`parseYoloDetections` → `DetectionStabilizer.update` → `SignalInterpreter.interpret`
→ `VoiceAlertController` → `TrafficVoiceService`

Path B (Countdown Timer):
`sign_number` ROI → `SignNumberPipelineService` → `NumberDetectionService`
→ `CountdownReadingStabilizer` → `CountdownAlertController`

`sign_number` does not enter the voting process. DetectionStabilizer — Used as an ROI
For cropping only (see `signClasses` vs `roiOnlyClasses` in detection_alert_config.dart)

## Safety Rules — Cannot be changed without reviewing the entire process

These values ​​are not general tuning settings. Do not adjust them to "make it respond faster" without considering:

- **Red light = `SignalAction.stop` always.** Remove all directional labels.
(`signal_interpreter.dart:_buildMessage`) Do not add a condition for the red light to become `go`.
- **Only numbers 1–5** become text. "Preparing to start" when the light is red.
Numbers outside this range are assigned to "Red Light - Stop/Wait".
- **`off_light` requires 12 consecutive frames / 6 seconds**, while other lights only require 4 out of 5 frames.
(`offLightMinimumFrames`, `offLightMinimumDuration`) This high threshold is to prevent
false positives from blinking lights — when it decreases, a normal blinking light becomes a "malfunction light".
- **VoiceAlertController can only speak one message at a time.** `_isSpeaking` prevents overlapping and selects
candidates from `priority` (lower number = more important). Parallel speaking is prohibited.
- **CountdownReadingStabilizer** immediately accepts if the number decreases to 0 or 1 (reduces latency).
However, if the number **increases**, more than 2 normal votes are required — this asymmetry is intentional.
- **`parseYoloDetections`** only discards entries with incomplete fields, not entire frames.
Data from the platform channel is considered untrusted. Always

## Program Scope (1.3.1) with classes in the model

11 classes: `turn_left`, `turn_right`, `go_straight_arrow`, `dont_turn_left`,
`dont_turn_right`, `dont_go_straight_arrow`, `red_light_circle`, `yellow_light`,
`green_light_circle`, `sign_number`, `off_light`

- Sections 3.10 (broken light) and 3.11 (blinking light) are combined into a single `off_light` class.
There is no separate class for the blinking light.
- `dont_go_straight_arrow` exists in the model and in the code, but is not yet specified in the scope documentation.
(Open, see tasks/todo.md)
- Thai names are available. **Two mismatched sets** intentionally:

`signal_interpreter.dart:thaiLabel` is the spoken language for drivers ("green light")

`traffic_detection_label_formatter.dart` is the official language for UI/reports
("green traffic light") Fix one, don't fix the other.

## Model updates (ADR-0001, docs/remote-model-update-guide.md)

The model bundled with the app is an offline fallback; check GitHub Releases.
Find the new `model_manifest.json` file in the background. (fire-and-forget during `main()`
via `RemoteModelUpdateBootstrap.checkOnce()`, Android only, once per session)

- Check **both size and SHA-256** before activating — `model_file_store.dart` checks
`contentLength` before loading, aborts if exceeded during loading, and then compares to the digest again.
Do not omit any steps.
- `ModelRegistry` stores 2 slots per modelId: `active` + `previous`. The `previous` is the only rollback available — once overwritten, there is no way to revert.
- `reportModelLoadFailure` marks that version as failed and moves `previous`
up to `active` — all 3 feature controllers must call this when YOLO fails to load.
- Models that change input/output contracts must bump `minimumAppVersion` in the manifest
and may still need to release an APK. New and improved:
- The manifest requires both the `traffic` and `number` keys.

## Conventions

- No need to write rules that `flutter_lints` already enforces; just run `flutter analyze` instead of hand-checking style.
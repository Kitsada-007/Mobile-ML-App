# Implementation Plan: Flutter File Structure Refactor

## Overview

Reorganize the Dart source into feature-first folders while preserving runtime
behavior. Shared configuration, models, model lifecycle code, utilities, and ML
inference primitives remain outside individual features. Tests mirror the
source layout so related production and test files are easy to locate.

## Architecture Decisions

- Keep `lib/main.dart` as the application entry point.
- Group user-facing flows under `lib/features/<feature>/`.
- Use `screens`, `widgets`, `controllers`, and `services` only where a feature
  actually needs them.
- Keep cross-feature ML inference code under `lib/core/services/inference/`.
- Keep application-wide model update and model selection code under
  `lib/core/services/model_management/`.
- Follow the requested feature names: `camera_detection`, `image_detection`,
  `video_detection`, and `settings`, each split into `data` and `presentation`
  where implementation exists.
- Preserve all public class names and behavior; this change only moves files
  and updates imports.

## Task List

### Phase 1: Shared foundations

- [x] Move shared inference services and their tests.
- [x] Move model-management services and their tests into `core`.
- [x] Verify the full test suite.

### Phase 2: Feature modules

- [x] Move camera source and tests into `features/camera_detection`.
- [x] Move settings and app-shell source into their feature/app folders.
- [x] Verify the full test suite.

### Phase 3: Media inference features

- [x] Move single-image source and tests into `features/image_detection`.
- [x] Move video source, widgets, services, and tests into
  `features/video_detection`.
- [x] Update application entry-point imports.

### Checkpoint: Complete

- [x] `flutter test --no-pub` passes (105 tests).
- [x] `flutter analyze --no-pub` completes with the 4 pre-existing warnings/info
  and no compile errors.
- [x] Android debug APK builds successfully.
- [x] No legacy `lib/presentation` or top-level `lib/services` Dart files remain.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Missed package import after a move | High | Search for every legacy import prefix and run the full suite after each phase. |
| Native model behavior changes accidentally | High | Make move-only changes; do not modify inference logic. |
| Existing untracked work is overwritten | High | Start only from a clean Git worktree and preserve existing task documents. |

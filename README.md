# trffic_ilght_app

A new Flutter project.

# Acknowledgement

This project is derived from the YOLO Flutter App
developed by Ultralytics.

Original Repository:
https://github.com/ultralytics/yolo-flutter-app

Licensed under AGPL-3.0.

## Documentation

- [Remote model update: step-by-step guide](docs/remote-model-update-guide.md)
- [Remote model update implementation plan](tasks/plan.md)
- [ADR-0001: GitHub Releases with bundled fallback](docs/decisions/0001-remote-model-updates-via-github-releases.md)
- [ADR-0002: Feature-first Flutter project structure](docs/decisions/0002-feature-first-flutter-structure.md)

## Project structure

```text
lib/
├── app/                         # App widget, shell, routes, and themes
├── core/
│   ├── config/                  # Application configuration
│   ├── services/
│   │   ├── inference/           # ML pipelines shared by multiple features
│   │   ├── model_management/    # Model download, verification, and selection
│   │   └── voice/               # Shared text-to-speech behavior
│   └── utils/                   # Framework-independent helpers
├── features/
│   ├── camera_detection/        # data/ and presentation/
│   ├── image_detection/         # presentation/
│   ├── video_detection/         # data/ and presentation/
│   └── settings/                # presentation/
├── shared/
│   └── models/                  # Types used across features
└── main.dart                    # Composition root and startup work
```

Tests mirror the production layout under `test/`. Add `data`, `repositories`,
or shared widget folders only when the corresponding implementation exists;
empty architectural layers are intentionally avoided.

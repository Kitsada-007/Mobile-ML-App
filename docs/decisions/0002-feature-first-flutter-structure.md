# ADR-0002: Use a feature-first Flutter project structure

## Status

Accepted

## Date

2026-08-02

## Context

The application grew from a small Flutter project into several distinct ML
flows: real-time camera detection, single-image detection, video detection,
settings, shared inference pipelines, and remote model management. Organizing
all screens, widgets, controllers, and services in global type-based folders
made a feature's files difficult to locate and allowed feature-specific logic
to mix with application-wide services.

The requested structure follows the familiar `screens`, `services`, `models`,
and `widgets` separation described by
[GeeksforGeeks](https://www.geeksforgeeks.org/flutter/flutter-file-structure/).
Flutter's current architecture guidance recommends clear UI and data
boundaries while treating the exact structure as adaptable to the application:
[Flutter architecture guide](https://docs.flutter.dev/app-architecture/guide).

## Decision

Use a feature-first structure:

- Place application composition, routes, and themes in `lib/app/`.
- Place user-facing flows in `lib/features/<feature>/`.
- Within a feature, separate `data/` from `presentation/` when both exist.
- Place cross-feature inference, model-management, and voice integrations in
  `lib/core/services/`.
- Place types shared by multiple features in `lib/shared/models/`.
- Mirror production paths under `test/`.
- Do not create empty repositories, error, constant, widget, label, or sound
  directories merely to satisfy a template.

## Alternatives considered

### Global folders by type

Keeping global `presentation/` and `services/` folders requires fewer moves,
but related feature files remain scattered as the application grows.

### Full clean architecture for every feature

Creating data sources, repositories, domain entities, use cases, and
presentation layers for every feature would provide strict boundaries, but
most of those layers have no current responsibility and would add navigation
cost without improving behavior or testability.

## Consequences

- A feature's UI and feature-specific services are now colocated.
- Shared native and ML integrations have one explicit home under `core`.
- Imports change, but public class names and runtime behavior remain stable.
- New layers should be added only when real responsibilities require them.
- Versioned model asset names remain unchanged because the remote-model update
  protocol and bundled fallback depend on those names.

# federated-package-architecture Specification

## Purpose
TBD - created by archiving change federated-native-webview. Update Purpose after archive.
## Requirements
### Requirement: Federated Package Layout
Papyrus SHALL use a Flutter federated plugin layout with a public package, a platform interface package, one platform implementation package per supported platform, an example application, documentation, and conformance test assets.

#### Scenario: Repository package structure is scaffolded
- **WHEN** the federated WebView change is implemented
- **THEN** the repository contains `packages/papyrus`, `packages/papyrus_platform_interface`, `packages/papyrus_android`, `packages/papyrus_ios`, `packages/papyrus_macos`, `packages/papyrus_windows`, `packages/papyrus_linux`, `examples/papyrus_example`, `docs`, `test/golden`, and `test/conformance`

### Requirement: Public Package Role
The `papyrus` package SHALL expose the Flutter-facing widget, controller, configuration, profile, request, event, error, capability, and extension APIs consumed by applications.

#### Scenario: Application imports public API
- **WHEN** an application depends on the public package
- **THEN** it can create a `PapyrusView`, configure a `PapyrusController`, load controlled web content, and subscribe to events without importing platform implementation packages directly

### Requirement: Platform Interface Role
The `papyrus_platform_interface` package SHALL define the shared platform contract, data models, method-channel boundaries, capability model, and mockable test interface used by all platform packages.

#### Scenario: Platform implementation registers through interface
- **WHEN** a platform package registers its implementation
- **THEN** it satisfies the shared platform interface and returns shared event, error, capability, and response models to the public package

### Requirement: Platform Package Independence
Each platform implementation package SHALL own native engine integration and native dependency configuration for exactly one platform family.

#### Scenario: Platform packages evolve independently
- **WHEN** a platform-specific WebView API changes
- **THEN** the affected platform package can adapt while preserving the shared platform interface contract


# papyrus_platform_interface

Platform interface package for the Papyrus federated plugin. Defines the shared
abstract platform class, data contracts, event types, and error types that all
platform implementations must satisfy.

This package is an implementation detail of `papyrus`. Application code should
depend on `papyrus`, not this package directly.

## Contents

- `PapyrusPlatform` — abstract base class all backends implement
- Load request, configuration, and capability models
- Policy contracts: `PapyrusSecurityPolicy`, `PapyrusNavigationPolicy`,
  `PapyrusStorageProfile`, `PapyrusInteractionPolicy`
- Platform event hierarchy: navigation, loading, resource, console, download,
  permission, renderer failure, scroll
- Error types: `PapyrusError`, `PapyrusNavigationBlockedError`,
  `PapyrusWebViewUnavailableError`

## Implementing a new platform

Extend `PapyrusPlatform` and register via `PapyrusPlatform.instance`. Refer to
an existing implementation (e.g. `papyrus_macos`) as a reference.

## Additional information

- [Repository](https://github.com/dizitart/papyrus)
- [Issue tracker](https://github.com/dizitart/papyrus/issues)

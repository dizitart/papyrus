## 0.2.0

* Added `PapyrusConfiguration.userAgent` field to override the session
  User-Agent string, serialized null-safely in `papyrusConfigurationToMap`.

## 0.1.1

* Added package-local LICENSE and example to improve pub.dev quality signals.

* Expanded API documentation coverage for public models and policies.

* Formatting and metadata refinements for pub score conformance.

## 0.1.0

* Initial release.
* Shared platform interface (`PapyrusPlatform`) for the Papyrus federated plugin.
* Data contracts: `PapyrusController`, `PapyrusLoadRequest`, `PapyrusCapabilities`,
  `PapyrusSecurityPolicy`, `PapyrusNavigationPolicy`, `PapyrusStorageProfile`,
  `PapyrusInteractionPolicy`.
* Platform event types: navigation, loading, resource interception, console,
  download, permission, renderer failure, and scroll events.
* Error types: `PapyrusError`, `PapyrusNavigationBlockedError`,
  `PapyrusWebViewUnavailableError`.

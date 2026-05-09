## 0.1.1

* Added package-local LICENSE and runnable package example.

* Expanded public API documentation for Papyrus controller and widget APIs.

* Documentation and metadata refinements for pub score conformance.

## 0.1.0

* Initial release.
* Public Flutter API: `PapyrusView` widget and `PapyrusController`.
* Federated plugin — delegates to the platform-specific backend on each target:
  `papyrus_android`, `papyrus_ios`, `papyrus_macos`, `papyrus_windows`,
  `papyrus_linux`.
* Policy models: `PapyrusSecurityPolicy`, `PapyrusNavigationPolicy`,
  `PapyrusStorageProfile`, `PapyrusInteractionPolicy`.
* `PapyrusController.getCapabilities()` for runtime feature detection.
* Load, navigation, resource interception, print, snapshot, auto-height,
  clear-cache / clear-storage surface.

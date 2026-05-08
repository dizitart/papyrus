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

## 0.2.0

* Applied `PapyrusConfiguration.userAgent` via `WebSettings.userAgentString`
  when set.

## 0.1.1

* Added package-local LICENSE and example to improve pub.dev quality signals.

* Expanded public API documentation coverage for Android implementation.

* Documentation and metadata refinements for pub score conformance.

## 0.1.0

* Initial release.
* Android System WebView backend for the Papyrus federated plugin.
* Maps `PapyrusSecurityPolicy`, navigation policy, and resource interception
  to Android WebView APIs using the native Flutter platform-view path.
* `shouldInterceptRequest` runs on a background thread; resource interception
  bridge dispatches to the main thread via `Handler.post`.
* Supports ephemeral storage, file-access constraints, dark-mode hint,
  mixed-content policy, download interception, and permission requests.

## 0.1.0

* Initial release.
* Android System WebView backend for the Papyrus federated plugin.
* Maps `PapyrusSecurityPolicy`, navigation policy, and resource interception
  to Android WebView APIs using the native Flutter platform-view path.
* `shouldInterceptRequest` runs on a background thread; resource interception
  bridge dispatches to the main thread via `Handler.post`.
* Supports ephemeral storage, file-access constraints, dark-mode hint,
  mixed-content policy, download interception, and permission requests.

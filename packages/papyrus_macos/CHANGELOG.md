## 0.1.0

* Initial release.
* macOS WKWebView backend for the Papyrus federated plugin.
* Uses the Flutter desktop overlay path by default; native AppKit platform-view
  path available via `PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW=true`.
* Sandboxed apps must add `com.apple.security.network.client` to both
  `DebugProfile.entitlements` and `Release.entitlements`.
* Supports print via `NSPrintOperation`, snapshot capture, ephemeral storage,
  and navigation/resource policy enforcement.

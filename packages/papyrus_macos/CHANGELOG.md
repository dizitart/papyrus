## 0.2.0

* Applied `PapyrusConfiguration.userAgent` via `WKWebView.customUserAgent`
  when set.

## 0.1.1

* Added package-local LICENSE and example to improve pub.dev quality signals.

* Expanded public API documentation coverage for macOS implementation.

* Documentation and metadata refinements for pub score conformance.

## 0.1.0

* Initial release.
* macOS WKWebView backend for the Papyrus federated plugin.
* Uses the Flutter desktop overlay path by default; native AppKit platform-view
  path available via `PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW=true`.
* Sandboxed apps must add `com.apple.security.network.client` to both
  `DebugProfile.entitlements` and `Release.entitlements`.
* Supports print via `NSPrintOperation`, snapshot capture, ephemeral storage,
  and navigation/resource policy enforcement.

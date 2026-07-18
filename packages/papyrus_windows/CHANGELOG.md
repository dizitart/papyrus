## 0.2.0

* Applied `PapyrusConfiguration.userAgent` via
  `ICoreWebView2Settings2::put_UserAgent` when set.

## 0.1.1

* Added package-local LICENSE and example to improve pub.dev quality signals.

* Expanded public API documentation coverage for Windows implementation.

* Documentation and metadata refinements for pub score conformance.

## 0.1.0

* Initial release.
* Windows WebView2 backend for the Papyrus federated plugin.
* Uses the Flutter desktop overlay model; initial loads are buffered until
  WebView2 environment and viewport are ready.
* Statically links the WebView2 loader — `WebView2Loader.dll` does not need
  to be shipped separately.
* Surfaces `webViewUnavailable` with diagnostics when WebView2 Runtime is absent.
* Navigation routed through `NavigationStarting` / `NewWindowRequested`;
  `clearCache` / `clearStorage` backed by profile browsing-data clearing.

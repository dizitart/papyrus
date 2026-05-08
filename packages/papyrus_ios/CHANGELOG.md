## 0.1.0

* Initial release.
* iOS WKWebView backend for the Papyrus federated plugin.
* Maps Papyrus policies to `WKWebViewConfiguration`, `WKNavigationDelegate`,
  non-persistent data store, and custom URL scheme handlers.
* Inline HTML is loaded via `data:` URL to align with the macOS WKWebView path.
* Supports ephemeral storage, file-access constraints, content-size observation
  for auto-height, snapshot capture, and print via `UIPrintInteractionController`.

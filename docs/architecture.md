# Architecture

Papyrus is a Flutter federated plugin:

- `packages/papyrus` exposes the public Flutter API.
- `packages/papyrus_platform_interface` owns shared contracts and models.
- `packages/papyrus_android` integrates Android System WebView.
- `packages/papyrus_ios` and `packages/papyrus_macos` integrate WKWebView.
- `packages/papyrus_windows` integrates WebView2.
- `packages/papyrus_linux` integrates WebKitGTK.

Platform packages translate native WebView behavior into the shared event,
error, resource, and capability contracts.


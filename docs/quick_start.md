# Quick Start

Papyrus exposes a generic Flutter widget and controller for controlled native
WebView rendering.

```dart
final controller = PapyrusController.create();

PapyrusView(
  controller: controller,
  configuration: PapyrusProfiles.documentViewer(),
  initialRequest: const PapyrusHtmlRequest(
    html: '<h1>Terms</h1><p>Controlled HTML content.</p>',
  ),
);
```

Use `PapyrusProfiles.lockedDown()` for untrusted static HTML and opt into more
permissive policies only when the content source is trusted.

On macOS, sandboxed apps must include the
`com.apple.security.network.client` entitlement for `WKWebView` to load
content reliably. Add it to both `DebugProfile.entitlements` and
`Release.entitlements` in the host runner.


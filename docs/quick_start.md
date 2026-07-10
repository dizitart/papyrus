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

## Custom User-Agent

Set `PapyrusConfiguration.userAgent` to override the session User-Agent. It is
applied globally by the native engine — covering sub-resources, XHR/fetch, and
`navigator.userAgent` — so servers and scripts can identify the embedding app.

```dart
PapyrusView(
  controller: controller,
  configuration: PapyrusProfiles.browserLike().copyWith(
    userAgent: 'MyApp-InAppWebView/1.0',
  ),
  initialRequest: PapyrusUriRequest(uri: Uri.parse('https://example.com')),
);
```

Leave it unset (`null`) to keep each platform's built-in User-Agent.

On macOS, sandboxed apps must include the
`com.apple.security.network.client` entitlement for `WKWebView` to load
content reliably. Add it to both `DebugProfile.entitlements` and
`Release.entitlements` in the host runner.

On Windows, ensure Microsoft Edge WebView2 Runtime is installed. If it is not
available, Papyrus reports `webViewUnavailable` with a host-readable message.


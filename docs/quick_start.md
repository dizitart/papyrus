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


---
name: papyrus
description: Use when adding Papyrus to a Flutter app, migrating WebView usage to Papyrus, rendering controlled HTML or email HTML with Papyrus, configuring Papyrus policies, troubleshooting Papyrus platform setup, or contributing to the Papyrus federated Flutter plugin.
---

# Papyrus Flutter Skill

Papyrus is a policy-driven federated native WebView for Flutter. Use it for controlled HTML rendering such as document viewers, email HTML panes, and sandboxed content panels. Do not present it as a general browser shell, and do not treat it as an HTML-to-Flutter-widget renderer.
For fastest and safest choices, pick a profile first in "Choose The Right Profile", then apply the matching recipe in "Common Recipes", and only then adjust individual policy fields.

## Repository Map

- Public app-facing API: `packages/papyrus/lib/papyrus.dart`
- Widget and controller: `packages/papyrus/lib/src/papyrus_view.dart`, `packages/papyrus/lib/src/papyrus_controller.dart`
- Shared models, profiles, policies, events, and capabilities: `packages/papyrus_platform_interface/lib/src/models.dart`
- Federated backends: `packages/papyrus_android`, `packages/papyrus_ios`, `packages/papyrus_macos`, `packages/papyrus_windows`, `packages/papyrus_linux`
- User docs: `docs/quick_start.md`, `docs/loading.md`, `docs/email_html_usage.md`, `docs/security.md`, `docs/platform_matrix.md`, `docs/capability_model.md`
- Example app: `examples/papyrus_example/lib/main.dart`

## Add Papyrus To A Flutter App

Add only the top-level package; federated backend packages are selected through Flutter plugin registration.

```yaml
dependencies:
  papyrus: ^0.1.0
```


Then run:

```bash
flutter pub get
```

Minimum environment expected by this repo: Flutter `>=3.41.0`, Dart `^3.11.0`.

## Minimal Widget Pattern

Use `PapyrusController.create()`, pass the controller into `PapyrusView`, and dispose the controller from the owning `State`.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:papyrus/papyrus.dart';

class HtmlPanel extends StatefulWidget {
  const HtmlPanel({super.key, required this.html});

  final String html;

  @override
  State<HtmlPanel> createState() => _HtmlPanelState();
}

class _HtmlPanelState extends State<HtmlPanel> {
  final PapyrusController _controller = PapyrusController.create();

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PapyrusView(
      controller: _controller,
      configuration: PapyrusProfiles.documentViewer(),
      initialRequest: PapyrusHtmlRequest(html: widget.html),
      onError: (event) => debugPrint('${event.code}: ${event.message}'),
    );
  }
}
```

Prefer `initialRequest` for first load. Use controller methods such as `loadHtmlString`, `loadUri`, `loadFile`, and `loadData` for later user-driven loads.

## Choose The Right Profile

- `PapyrusProfiles.lockedDown()`: untrusted static HTML. JavaScript, storage, remote resources, file access, popups, and navigation are conservative by default.
- `PapyrusProfiles.documentViewer()`: controlled document viewing. Remote resources ask the host app; navigation opens externally by default.
- `PapyrusProfiles.emailHtmlViewer()`: sanitized email bodies. Remote resources are blocked, JavaScript and storage are disabled, navigation is external/user-gesture oriented, and auto-height is enabled.
- `PapyrusProfiles.trustedAppContent()`: app-owned content that may need restricted JavaScript and host-allowlisted resources/storage.
- `PapyrusProfiles.browserLike()`: only for trusted browser-like surfaces. This loosens JavaScript, navigation, remote-resource, popup, and storage policy.

When in doubt, start locked down and opt into specific policy fields with `copyWith`.

## Loading Content

Use typed requests so platform behavior stays explicit:

- `PapyrusHtmlRequest(html: ..., baseUri: ..., metadata: ..., virtualResources: ...)`
- `PapyrusUriRequest(uri: ..., headers: ...)`
- `PapyrusFileRequest(absolutePath: ...)`
- `PapyrusDataRequest(bytes: ..., mimeType: ..., encoding: ..., baseUri: ...)`

`PapyrusHtmlRequest` ensures an HTML shell and viewport meta. It can inject a caller-supplied Content Security Policy, but Papyrus does not sanitize HTML or CSS in any profile.

For app-owned inline assets, pass `PapyrusVirtualResource` instances and set a virtual origin:

```dart
final configuration = PapyrusProfiles.emailHtmlViewer().copyWith(
  resources: PapyrusResourcePolicy(
    remoteResources: PapyrusRemoteResourceMode.block,
    virtualResourceOrigin: Uri.parse('papyrus-resource://message.local/'),
  ),
);

await controller.load(
  PapyrusHtmlRequest(
    html: sanitizedHtml,
    baseUri: Uri.parse('papyrus-resource://message.local/'),
    virtualResources: inlineResources,
  ),
);
```

Pass that `configuration` to `PapyrusView`.

## Custom User-Agent

Set `PapyrusConfiguration.userAgent` to override the session User-Agent on every
backend. When non-null it applies globally (sub-resources, XHR/fetch, and
`navigator.userAgent`), not just the first document request. Leave it null to
keep the platform default.

```dart
final configuration = PapyrusProfiles.browserLike().copyWith(
  userAgent: 'MyApp-InAppWebView/1.0',
);
```

## Host Policy Hooks

Use callbacks for decisions that depend on app state:

```dart
PapyrusView(
  controller: controller,
  configuration: PapyrusProfiles.documentViewer(),
  onNavigationRequest: (request) async {
    if (request.uri.host == 'trusted.example') {
      return PapyrusNavigationDecision.allow;
    }
    return PapyrusNavigationDecision.openExternally;
  },
  onResourceRequest: (request) async {
    if (request.resourceType == PapyrusResourceType.image) {
      return const PapyrusBlockResource();
    }
    return const PapyrusAllowResource();
  },
);
```

Use `PapyrusRespondWithResource(PapyrusResourceResponse(...))` when the app should serve bytes itself.

## Capabilities And Optional Features

Always query capabilities before relying on optional behavior:

```dart
final capabilities = await controller.getCapabilities();
if (capabilities.supportsSnapshot) {
  final png = await controller.captureSnapshot();
}
```

Capabilities cover resource interception, virtual schemes, ephemeral storage, print, snapshot, auto-height, dark mode, download interception, and permission interception. The docs matrix is informative; runtime capabilities are authoritative.

## Platform Setup Notes

- Android uses Android System WebView.
- iOS and macOS use WKWebView. Sandboxed macOS apps need `com.apple.security.network.client` in both `DebugProfile.entitlements` and `Release.entitlements`.
- macOS uses the desktop overlay path by default. Set `PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW=true` only when explicitly testing the AppKit platform-view path.
- Windows uses WebView2. The end-user machine must have Microsoft Edge WebView2 Runtime installed.
- Linux uses WebKitGTK. Install `webkit2gtk-4.1` where available, with `webkit2gtk-4.0` as the fallback family on older distros.

## Security Rules

- Papyrus is not a sanitizer. Sanitize untrusted HTML, CSS, URLs, and MIME-derived content before loading.
- Keep JavaScript disabled unless content is trusted and the feature needs it.
- Keep file access and universal file URL access disabled unless there is a narrow, reviewed reason.
- Prefer ephemeral storage for documents and email. Use persistent cookies or local storage only for trusted app content.
- Treat remote images, fonts, scripts, iframes, media, downloads, and permissions as host policy decisions.
- Do not use `browserLike()` for email, untrusted documents, or preview panes.

## Common Recipes

Document viewer:

```dart
final config = PapyrusProfiles.documentViewer().copyWith(
  display: const PapyrusDisplayPolicy(autoHeight: true),
);
PapyrusView(
  controller: controller,
  configuration: config,
  initialRequest: PapyrusHtmlRequest(html: html, baseUri: baseUri),
);
```

Email HTML viewer:

```dart
final config = PapyrusProfiles.emailHtmlViewer();
PapyrusView(
  controller: controller,
  configuration: config,
  initialRequest: PapyrusHtmlRequest(
    html: sanitizedEmailHtml,
    baseUri: messageBaseUri,
    metadata: const PapyrusContentMetadata(source: 'email'),
    virtualResources: cidResources,
  ),
);
```

Trusted app content:

```dart
final config = PapyrusProfiles.trustedAppContent().copyWith(
  resources: const PapyrusResourcePolicy(
    remoteResources: PapyrusRemoteResourceMode.allowByHost,
    allowedHosts: {'assets.example.com'},
  ),
);
```

Selection tools:

```dart
final selected = await controller.selectedText();
final quote = await controller.quoteSelection();
await controller.copySelection();
```

## Contributing Inside This Repo

Use the existing federated boundaries:

- Public API changes usually touch `packages/papyrus`, `packages/papyrus_platform_interface`, docs, and tests.
- Shared policy/model changes belong in `packages/papyrus_platform_interface`.
- Backend behavior belongs in the platform package that owns the native engine.
- Keep app-facing examples in `examples/papyrus_example`.

Run the repository contract checks from the root:

```bash
./tool/check.sh
```

For live backend conformance, list devices with `flutter devices`, then run:

```bash
dart run tool/run_platform_conformance.dart --device macos
dart run tool/run_platform_conformance.dart --device macos --native-macos-platform-view
dart run tool/run_platform_conformance.dart --device emulator-5554 --skip-checks
dart run tool/run_platform_conformance.dart --device linux --skip-checks
dart run tool/run_platform_conformance.dart --device windows --skip-checks
```

Known validation nuance: `loadData` is still primarily contract-tested, macOS print can enter an interactive flow under `flutter test`, and Linux/Windows live behavior needs validation on matching hosts.

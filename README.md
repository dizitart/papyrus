# Papyrus

[![pub package](https://img.shields.io/pub/v/papyrus.svg)](https://pub.dev/packages/papyrus)
[![CI](https://github.com/dizitart/papyrus/actions/workflows/ci.yml/badge.svg)](https://github.com/dizitart/papyrus/actions/workflows/ci.yml)
[![Publish to pub.dev](https://github.com/dizitart/papyrus/actions/workflows/publish.yml/badge.svg)](https://github.com/dizitart/papyrus/actions/workflows/publish.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

<p align="center">
  <img src="docs/logo.png" width="256" alt="Papyrus logo">
</p>

A policy-driven federated native WebView for Flutter. Papyrus embeds the platform system WebView on each supported target and exposes a uniform, conservative-by-default API surface for loading, navigation, resource, security, storage, and interaction control.

Papyrus is designed for controlled HTML rendering use-cases — document viewers, email HTML renderers, sandboxed content panels — not as a general-purpose browser shell.

---

## Release & Publishing

- Release runbook: [docs/release_workflow.md](docs/release_workflow.md)
- CI workflow: [.github/workflows/ci.yml](.github/workflows/ci.yml)
- Publish workflow: [.github/workflows/publish.yml](.github/workflows/publish.yml)

---

## Packages

| Package | Description |
|---|---|
| `papyrus` | Public Flutter API — `PapyrusView`, `PapyrusController`, policies, profiles |
| `papyrus_platform_interface` | Shared contracts, models, events, and the platform abstract base |
| `papyrus_android` | Android System WebView backend |
| `papyrus_ios` | WKWebView backend (iOS) |
| `papyrus_macos` | WKWebView backend (macOS) |
| `papyrus_windows` | WebView2 backend |
| `papyrus_linux` | WebKitGTK backend |

---

## Platform Support

| Platform | Engine | Embedded View | Resource Interception | Ephemeral Storage | Print | Snapshot | Auto-Height |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Android | Android System WebView | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| iOS | WKWebView | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| macOS | WKWebView | ✓ (overlay) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Windows | WebView2 | ✓ (overlay) | ✓ | Partial | ✓ | Partial | ✓ |
| Linux | WebKitGTK | ✓ (overlay) | Feasible | ✓ | Partial | Partial | ✓ |

> **Note:** Windows and Linux use a Flutter-owned placeholder and a native overlay; macOS uses the overlay path by default. Runtime capability queries via `PapyrusController.getCapabilities()` are always authoritative.

---

## Requirements

- Flutter `>=3.41.0`
- Dart SDK `^3.11.0`

### macOS

Sandboxed macOS apps must include the `com.apple.security.network.client` entitlement in both `DebugProfile.entitlements` and `Release.entitlements` for `WKWebView` to load content reliably.

### Windows

Windows hosts must have Microsoft Edge WebView2 Runtime installed.
Papyrus links the WebView2 loader statically — `WebView2Loader.dll` does not
need to be shipped with the app.

| Distribution strategy | Installer | Best for |
|---|---|---|
| Evergreen Bootstrapper | `MicrosoftEdgeWebView2Setup.exe /silent /install` | Consumer apps with internet access |
| Evergreen Standalone | Architecture-specific offline installer from Microsoft | Offline or enterprise |

If runtime creation fails, Papyrus surfaces a structured `webViewUnavailable`
error. See [`papyrus_windows` README](packages/papyrus_windows/README.md) for
the full packaging checklist.

### macOS

WKWebView is a system framework included with macOS — no WebKit redistributable
is needed in the app bundle. Minimum supported macOS is 10.15 (Catalina).

For notarized and App Store distributions, include the
`com.apple.security.network.client` entitlement in both `DebugProfile.entitlements`
and `Release.entitlements` so WKWebView can make network connections.

### Linux

Linux hosts must have WebKitGTK installed via the system package manager.
Papyrus probes for `webkit2gtk-4.1` first and falls back to `webkit2gtk-4.0`.

| Distribution | webkit2gtk 4.1 package | webkit2gtk 4.0 fallback |
|---|---|---|
| Ubuntu 22.04 LTS / Debian 12 | `libwebkit2gtk-4.1-0` | `libwebkit2gtk-4.0-0` |
| Ubuntu 24.04 LTS | `libwebkit2gtk-4.1-0` | — |
| Fedora 39+ | `webkit2gtk4.1` | `webkit2gtk3` |
| openSUSE Tumbleweed | `libwebkit2gtk3-4_1-0` | `libwebkit2gtk3-0` |
| Arch Linux | `webkit2gtk-4.1` | `webkit2gtk` |

GTK 3 (`gtk+-3.0`) is also required; it is present by default on all major
desktop distributions. See [`papyrus_linux` README](packages/papyrus_linux/README.md)
for distro-specific install commands and AppImage/Snap guidance.

---

## Installation

Add `papyrus` to your `pubspec.yaml`:

```yaml
dependencies:
  papyrus:
    path: packages/papyrus   # or pub.dev version once published
```

---

## Quick Start

```dart
import 'package:papyrus/papyrus.dart';
import 'package:flutter/material.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final _controller = PapyrusController.create();

  @override
  Widget build(BuildContext context) {
    return PapyrusView(
      controller: _controller,
      configuration: PapyrusProfiles.documentViewer(),
      initialRequest: const PapyrusHtmlRequest(
        html: '<h1>Hello Papyrus</h1><p>Controlled HTML content.</p>',
      ),
      onPageFinished: (event) => debugPrint('Loaded: ${event.uri}'),
    );
  }
}
```

Use `PapyrusProfiles.lockedDown()` for untrusted static HTML. Opt into more permissive profiles only when the content source is trusted.

---

## Core API

### `PapyrusController`

Create a controller with `PapyrusController.create()`. The controller is the primary handle to all WebView operations.

#### Content Loading

| Method | Description |
|---|---|
| `load(PapyrusLoadRequest)` | Load content using a typed request object |
| `loadHtmlString(html, {baseUri, metadata})` | Convenience — load an HTML string |
| `loadUri(uri, {headers})` | Convenience — load a URI with optional headers |
| `loadFile(absolutePath)` | Load a local file by absolute path |
| `loadData(bytes, mimeType, {encoding, baseUri})` | Load raw bytes with a MIME type |
| `reload()` | Reload the current page |
| `stopLoading()` | Stop the current load |

#### Navigation

| Method | Description |
|---|---|
| `canGoBack()` | Returns `true` if there is a back history entry |
| `canGoForward()` | Returns `true` if there is a forward history entry |
| `goBack()` | Navigate back |
| `goForward()` | Navigate forward |
| `currentUri()` | Return the currently loaded URI |
| `title()` | Return the current page title |
| `estimatedProgress()` | Return the estimated load progress (0.0–1.0) |

#### JavaScript

| Method | Description |
|---|---|
| `evaluateJavaScript(source)` | Evaluate a JavaScript expression and return the result |
| `addJavaScriptChannel(name)` | Register a named message channel from page → host |
| `removeJavaScriptChannel(name)` | Unregister a named message channel |

#### Text Selection

| Method | Description |
|---|---|
| `selectedText()` | Return the currently selected text |
| `copySelection()` | Copy the current selection to the clipboard |
| `quoteSelection({prefix})` | Return the selection with each line prefixed (default `> `) |

#### Output & Export

| Method | Description |
|---|---|
| `captureSnapshot({options})` | Capture a PNG snapshot as `Uint8List` |
| `printDocument({options})` | Trigger the native print dialog |
| `getContentSize()` | Return the scrollable content size as `PapyrusContentSize` |

#### Storage

| Method | Description |
|---|---|
| `clearCache()` | Clear the HTTP cache |
| `clearStorage(options)` | Clear cookies, local storage, and/or cache selectively |

#### Platform

| Method | Description |
|---|---|
| `getCapabilities()` | Query `PapyrusPlatformCapabilities` for supported features |
| `dispose()` | Release the underlying native WebView |

#### Events

```dart
controller.events.listen((event) {
  switch (event) {
    case PapyrusPageStartedEvent(:final uri): ...
    case PapyrusPageFinishedEvent(:final uri): ...
    case PapyrusProgressEvent(:final progress): ...
  }
});
```

---

### `PapyrusView`

The Flutter widget that embeds the native WebView. All constructor parameters are live — updating `controller`, `configuration`, or `initialRequest` triggers a full reinitialisation.

| Parameter | Type | Description |
|---|---|---|
| `controller` | `PapyrusController` | **Required.** The controlling handle |
| `initialRequest` | `PapyrusLoadRequest?` | Content to load when the view is created |
| `configuration` | `PapyrusConfiguration` | Policy configuration (defaults to locked-down) |
| `gestureRecognizers` | `Set<Factory<...>>?` | Custom gesture recognizers for embedded view |
| `onCreated` | `ValueChanged<PapyrusController>?` | Called when the native view is ready |
| `onPageStarted` | `ValueChanged<PapyrusPageStartedEvent>?` | Called when navigation begins |
| `onPageFinished` | `ValueChanged<PapyrusPageFinishedEvent>?` | Called when the page finishes loading |
| `onProgressChanged` | `ValueChanged<PapyrusProgressEvent>?` | Called during loading with progress 0.0–1.0 |
| `onNavigationRequest` | `Future<PapyrusNavigationDecision> Function(...)?` | Policy hook for each navigation |
| `onResourceRequest` | `Future<PapyrusResourceDecision> Function(...)?` | Policy hook for each resource request |
| `onDownloadRequest` | `Future<PapyrusDownloadDecision> Function(...)?` | Called when the browser triggers a download |
| `onPermissionRequest` | `Future<PapyrusPermissionDecision> Function(...)?` | Called for camera/mic/geo/etc. requests |
| `onConsoleMessage` | `ValueChanged<PapyrusConsoleMessage>?` | Called for console log output |
| `onWebMessage` | `ValueChanged<PapyrusWebMessage>?` | Called for messages posted via JS channels |
| `onError` | `ValueChanged<PapyrusErrorEvent>?` | Called on load or render errors |
| `onContentSizeChanged` | `ValueChanged<PapyrusContentSize>?` | Called when scrollable content size changes |

---

## Configuration & Policies

All policy is declared through `PapyrusConfiguration`, which composes ten discrete policy objects. Every field has a conservative default — nothing is permitted unless explicitly enabled.

```dart
const config = PapyrusConfiguration(
  security: PapyrusSecurityPolicy(...),
  navigation: PapyrusNavigationPolicy(...),
  resources: PapyrusResourcePolicy(...),
  javascript: PapyrusJavaScriptPolicy(...),
  storage: PapyrusStoragePolicy(...),
  media: PapyrusMediaPolicy(...),
  display: PapyrusDisplayPolicy(...),
  accessibility: PapyrusAccessibilityPolicy(...),
  interaction: PapyrusInteractionPolicy(...),
  platform: PapyrusPlatformOptions(...),
);
```

### `PapyrusSecurityPolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `allowJavaScript` | `bool` | `false` | Enable JavaScript execution |
| `allowInlineMediaPlayback` | `bool` | `false` | Allow inline media playback |
| `allowFileAccess` | `bool` | `false` | Allow `file://` URI access |
| `allowUniversalAccessFromFileUrls` | `bool` | `false` | Allow cross-origin file-URL access |
| `allowPopups` | `bool` | `false` | Allow popup window creation |
| `allowMixedContent` | `bool` | `false` | Allow mixed HTTP/HTTPS content |
| `allowClipboardRead` | `bool` | `false` | Allow page clipboard read access |
| `allowClipboardWrite` | `bool` | `false` | Allow page clipboard write access |
| `allowGeolocation` | `bool` | `false` | Allow geolocation API |
| `allowCamera` | `bool` | `false` | Allow camera access |
| `allowMicrophone` | `bool` | `false` | Allow microphone access |
| `allowProtectedMedia` | `bool` | `false` | Allow DRM / protected media |
| `enableContentIsolation` | `bool` | `true` | Enable renderer content isolation |
| `contentSecurityPolicy` | `String?` | `null` | CSP injected into HTML string loads |

### `PapyrusNavigationPolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `defaultDecision` | `PapyrusNavigationDecision` | `block` | Fallback decision when no rule matches |
| `allowedSchemes` | `Set<String>` | `{'https'}` | Schemes allowed to load in the WebView |
| `externalSchemes` | `Set<String>` | `{'http','https','mailto','tel'}` | Schemes to open externally |
| `blockedSchemes` | `Set<String>` | `{'javascript','data','file'}` | Schemes always blocked |
| `requireUserGestureForExternalOpen` | `bool` | `true` | Require user gesture for external opens |
| `allowMainFrameNavigation` | `bool` | `false` | Allow main-frame navigations |
| `allowSubFrameNavigation` | `bool` | `false` | Allow sub-frame (iframe) navigations |

### `PapyrusResourcePolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `remoteResources` | `PapyrusRemoteResourceMode` | `block` | Remote resource loading mode |
| `allowedHosts` | `Set<String>` | `{}` | Hosts allowed under `allowByHost` mode |
| `allowedSchemes` | `Set<String>` | `{'https'}` | Schemes allowed for resources |
| `blockedResourceTypes` | `Set<PapyrusResourceType>` | `{}` | Resource types to block unconditionally |
| `virtualResourceOrigin` | `Uri?` | `null` | Base URI for virtual (in-memory) resources |
| `enableRequestInterception` | `bool` | `true` | Enable the resource-request interception hook |

### `PapyrusJavaScriptPolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `mode` | `PapyrusJavaScriptMode` | `disabled` | JavaScript execution mode |
| `allowedChannels` | `Set<String>` | `{}` | Named channels the page may post messages to |
| `allowUserScripts` | `bool` | `false` | Allow user-authored script injection |
| `injectedScripts` | `List<PapyrusUserScript>` | `[]` | Scripts injected by the host |

### `PapyrusStoragePolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `cookies` | `PapyrusCookiePolicy` | `block` | Cookie storage policy |
| `localStorage` | `PapyrusStorageMode` | `disabled` | Local/session storage policy |
| `cache` | `PapyrusCacheMode` | `defaultMode` | HTTP cache policy |
| `ephemeral` | `bool` | `true` | Use an ephemeral (in-memory) session |
| `partitionId` | `String?` | `null` | Identifier for a partitioned storage profile |

### `PapyrusMediaPolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `autoPlay` | `bool` | `false` | Allow media autoplay |
| `inlinePlayback` | `bool` | `false` | Allow inline video playback |
| `requireUserGesture` | `bool` | `true` | Require user gesture to start playback |
| `allowFullscreen` | `bool` | `false` | Allow fullscreen video |

### `PapyrusDisplayPolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `autoHeight` | `bool` | `false` | Expand the widget to fit content height |
| `minimumHeight` | `double?` | `null` | Minimum height in logical pixels |
| `maximumHeight` | `double?` | `null` | Maximum height in logical pixels |
| `zoomEnabled` | `bool` | `true` | Allow pinch-to-zoom |
| `textZoom` | `double` | `1.0` | Text zoom multiplier |
| `backgroundColor` | `int?` | `null` | Background color as ARGB integer |
| `darkMode` | `PapyrusDarkMode` | `system` | Dark-mode preference |
| `viewport` | `PapyrusViewportPolicy` | width=device-width, scale=1.0 | Viewport meta settings |
| `measurement` | `PapyrusMeasurementPolicy` | observe=true, debounce=50ms | Content-size measurement settings |

### `PapyrusAccessibilityPolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `enableNativeSemantics` | `bool` | `true` | Forward native WebView accessibility tree to Flutter |

### `PapyrusInteractionPolicy`

| Field | Type | Default | Description |
|---|---|---|---|
| `allowTextSelection` | `bool` | `true` | Allow text selection |
| `allowContextMenu` | `bool` | `true` | Allow the default context menu |
| `allowLongPress` | `bool` | `true` | Allow long-press interaction |

### `PapyrusPlatformOptions`

| Field | Type | Default | Description |
|---|---|---|---|
| `debuggingEnabled` | `bool` | `false` | Enable WebView remote debugging |
| `hardwareAcceleration` | `PapyrusHardwareAccelerationMode` | `auto` | Hardware acceleration mode |

---

## Built-In Configuration Profiles

`PapyrusProfiles` provides ready-made `PapyrusConfiguration` instances for common use cases. They are a starting point — use `copyWith` to adjust individual sub-policies.

| Profile | Use Case |
|---|---|
| `PapyrusProfiles.lockedDown()` | Maximally restricted — no JS, no remote resources, all navigation blocked |
| `PapyrusProfiles.documentViewer()` | Static documents — remote resources ask the host, external navigation opens externally |
| `PapyrusProfiles.trustedAppContent()` | Trusted in-app content — restricted JS, per-host resources, cookies + storage |
| `PapyrusProfiles.browserLike()` | Unrestricted browsing — full JS, all navigation, cookies, and storage |
| `PapyrusProfiles.emailHtmlViewer()` | Sanitized email HTML — no remote resources, no JS, no navigation, auto-height |

```dart
// Start from a profile and override one policy group
final config = PapyrusProfiles.documentViewer().copyWith(
  display: const PapyrusDisplayPolicy(autoHeight: true, darkMode: PapyrusDarkMode.dark),
);
```

---

## Load Requests

All content is loaded via a sealed `PapyrusLoadRequest` hierarchy.

### `PapyrusHtmlRequest`

```dart
PapyrusHtmlRequest(
  html: sanitizedHtmlString,
  baseUri: Uri.parse('papyrus-resource://message/42/'),
  metadata: const PapyrusContentMetadata(
    contentType: 'text/html',
    source: 'email',
    identifier: 'message-42',
  ),
  virtualResources: [
    PapyrusVirtualResource(
      uri: Uri.parse('papyrus-resource://message/42/image.png'),
      bytes: imageBytes,
      mimeType: 'image/png',
    ),
  ],
);
```

Use `withContentSecurityPolicy(policy)` to inject a `Content-Security-Policy` meta tag into the document.

### `PapyrusUriRequest`

```dart
PapyrusUriRequest(
  uri: Uri.parse('https://example.com/article'),
  headers: {'Authorization': 'Bearer token'},
);
```

### `PapyrusFileRequest`

```dart
PapyrusFileRequest(absolutePath: '/data/user/0/com.example/files/doc.html');
```

### `PapyrusDataRequest`

```dart
PapyrusDataRequest(
  bytes: pdfBytes,
  mimeType: 'application/pdf',
  encoding: 'base64',
  baseUri: Uri.parse('https://example.com/'),
);
```

---

## Virtual Resources

Virtual resources allow app-owned bytes (inline images, CSS, fonts) to be served from an in-memory origin, without writing them to disk.

**Inline resources (per load request):**

```dart
PapyrusHtmlRequest(
  html: '<img src="papyrus-resource://host/logo.png">',
  virtualResources: [
    PapyrusVirtualResource(
      uri: Uri.parse('papyrus-resource://host/logo.png'),
      bytes: assetBytes,
      mimeType: 'image/png',
    ),
  ],
);
```

**Dynamic provider (global registry):**

```dart
class MyImageProvider implements PapyrusVirtualResourceProvider {
  @override
  Future<PapyrusResourceResponse?> resolve(PapyrusResourceRequest request) async {
    if (request.uri.path == '/logo.png') {
      return PapyrusResourceResponse(
        bytes: await loadAssetBytes('assets/logo.png'),
        mimeType: 'image/png',
      );
    }
    return null; // fall through to next provider
  }
}
```

---

## Navigation Policy Callbacks

Intercept navigation at runtime from `PapyrusView.onNavigationRequest`:

```dart
PapyrusView(
  controller: _controller,
  configuration: PapyrusProfiles.documentViewer(),
  onNavigationRequest: (request) async {
    if (request.uri.host == 'trusted.example.com') {
      return PapyrusNavigationDecision.allow;
    }
    return PapyrusNavigationDecision.openExternally;
  },
);
```

`PapyrusNavigationRequest` exposes:

| Property | Type | Description |
|---|---|---|
| `uri` | `Uri` | The navigation target |
| `isMainFrame` | `bool` | Whether this is a main-frame navigation |
| `navigationType` | `PapyrusNavigationType` | Link, form, reload, back/forward, programmatic, other |
| `hasUserGesture` | `bool` | Whether a user gesture triggered the navigation |

**Navigation decisions:**

| Decision | Behaviour |
|---|---|
| `allow` | Let the WebView navigate |
| `block` | Silently cancel the navigation |
| `openExternally` | Hand the URI to the platform URL launcher |
| `download` | Route as a download request |

---

## Resource Policy Callbacks

Intercept resource requests at runtime from `PapyrusView.onResourceRequest`:

```dart
PapyrusView(
  controller: _controller,
  onResourceRequest: (request) async {
    if (request.resourceType == PapyrusResourceType.image &&
        request.uri.host != 'cdn.example.com') {
      return const PapyrusBlockResource();
    }
    return const PapyrusAllowResource();
  },
);
```

**Resource decisions:**

| Class | Description |
|---|---|
| `PapyrusAllowResource` | Let the network request proceed |
| `PapyrusBlockResource` | Cancel the request |
| `PapyrusRespondWithResource(response)` | Respond with host-provided bytes |

---

## Download & Permission Callbacks

```dart
PapyrusView(
  controller: _controller,
  onDownloadRequest: (request) async {
    // request.uri, request.suggestedFilename, request.mimeType, request.contentLength
    return PapyrusDownloadDecision.handToHostApp;
  },
  onPermissionRequest: (request) async {
    // request.uri, request.permissions (Set<PapyrusPermissionType>)
    if (request.permissions.contains(PapyrusPermissionType.camera)) {
      return PapyrusPermissionDecision.deny;
    }
    return PapyrusPermissionDecision.promptHostApp;
  },
);
```

---

## Platform Capabilities

Before using optional features, query the runtime capabilities of the current backend:

```dart
final caps = await controller.getCapabilities();

if (caps.supportsSnapshot) {
  final png = await controller.captureSnapshot();
}

if (caps.supportsPrint) {
  await controller.printDocument(options: const PapyrusPrintOptions(jobName: 'Report'));
}

if (caps.supportsAutoHeight) {
  // PapyrusDisplayPolicy.autoHeight is effective on this backend
}
```

`PapyrusPlatformCapabilities` fields:

| Field | Description |
|---|---|
| `supportsResourceInterception` | Backend can intercept resource requests |
| `supportsVirtualSchemes` | Backend supports virtual resource origins |
| `supportsEphemeralStorage` | Backend supports in-memory session storage |
| `supportsPrint` | Backend supports `printDocument` |
| `supportsSnapshot` | Backend supports `captureSnapshot` |
| `supportsAutoHeight` | Backend supports content-height measurement |
| `supportsDarkMode` | Backend supports forced dark-mode preference |
| `supportsDownloadInterception` | Backend can intercept download requests |
| `supportsPermissionInterception` | Backend can intercept permission requests |

---

## Enumerations

### `PapyrusNavigationType`
`linkClicked` · `formSubmitted` · `backForward` · `reload` · `programmatic` · `other`

### `PapyrusNavigationDecision`
`allow` · `block` · `openExternally` · `download`

### `PapyrusResourceType`
`document` · `stylesheet` · `image` · `font` · `script` · `xhr` · `media` · `iframe` · `other`

### `PapyrusRemoteResourceMode`
`block` · `allowAll` · `allowByHost` · `askHostApp`

### `PapyrusJavaScriptMode`
`disabled` · `restricted` · `unrestricted`

### `PapyrusCookiePolicy`
`block` · `allow` · `allowByHost`

### `PapyrusStorageMode`
`disabled` · `enabled`

### `PapyrusCacheMode`
`defaultMode` · `noCache` · `cacheOnly`

### `PapyrusPermissionType`
`camera` · `microphone` · `geolocation` · `notifications` · `clipboardRead` · `clipboardWrite` · `protectedMedia` · `fileChooser`

### `PapyrusPermissionDecision`
`grant` · `deny` · `promptHostApp`

### `PapyrusDownloadDecision`
`block` · `allowSystemDownload` · `handToHostApp`

### `PapyrusDarkMode`
`system` · `light` · `dark`

### `PapyrusHardwareAccelerationMode`
`auto` · `hardware` · `software`

### `PapyrusErrorCode`
`unknown` · `navigationBlocked` · `resourceBlocked` · `networkFailed` · `sslFailed` · `timeout` · `rendererCrashed` · `unsupportedPlatformFeature` · `invalidLoadRequest` · `webViewUnavailable`

---

## Error Handling

Errors are surfaced both through the event stream and through the `onError` callback on `PapyrusView`.

```dart
PapyrusView(
  controller: _controller,
  onError: (event) {
    debugPrint('WebView error: ${event.code} — ${event.message}');
  },
);
```

Platform operations that are not available on the current backend throw a `PapyrusException` with `PapyrusErrorCode.unsupportedPlatformFeature`. Always check `getCapabilities()` before calling optional methods.

---

## Email HTML Rendering

Papyrus is well-suited for rendering sanitized email HTML. The application remains responsible for MIME parsing, charset decoding, CID extraction, HTML sanitization, and link rewriting. Papyrus handles secure sandboxed display.

```dart
final config = PapyrusProfiles.emailHtmlViewer().copyWith(
  resources: PapyrusResourcePolicy(
    remoteResources: PapyrusRemoteResourceMode.block,
    virtualResourceOrigin: Uri.parse('papyrus-resource://email.local/'),
  ),
);

await controller.load(
  PapyrusHtmlRequest(
    html: preparedEmail.sanitizedHtml,
    baseUri: preparedEmail.baseUri,
    virtualResources: preparedEmail.inlineResources,
  ),
);
```

The `emailHtmlViewer` profile enforces:
- No JavaScript
- No remote resource loading
- No main- or sub-frame navigation
- Ephemeral session (no cookies, no local storage)
- Auto-height content measurement

---

## Security Defaults

Papyrus ships with a locked-down default configuration:

- JavaScript is **disabled**
- Popups are **disabled**
- File access and universal file-URL access are **disabled**
- Mixed content is **blocked** where the native engine supports it
- Device permissions (camera, mic, geolocation) are **denied or handed to the host**
- Navigation is **intercepted** — nothing loads without explicit policy permission
- Downloads are **surfaced to the host**
- Cookies and local storage are **blocked** in strict profiles

> **Important:** Papyrus does not sanitize HTML or CSS. Applications that render untrusted content **must sanitize before passing content to Papyrus**.

---

## Migrating from `webview_flutter`

1. Create a controller with `PapyrusController.create()`.
2. Replace your WebView widget with `PapyrusView`.
3. Choose an explicit `PapyrusProfiles` preset.
4. Move navigation, resource, permission, and download decisions into Papyrus policy callbacks.
5. Query `PapyrusPlatformCapabilities` before using optional features (print, snapshot, auto-height).

Papyrus is not a browser shell — it does not include tabs, bookmarks, address bar UI, MIME parsing, or HTML sanitization.

---

## Development & Testing

### Run static checks and unit tests

```bash
bash tool/check.sh
```

### Run full platform conformance (contract + live device)

```bash
dart run tool/run_platform_conformance.dart --device <flutter-device-id>
```

Available flags:

| Flag | Description |
|---|---|
| `--skip-checks` | Skip the static-check and contract layer |
| `--skip-smoke` | Skip the native backend smoke suite |
| `--skip-api` | Skip the public API conformance suite |
| `--native-macos-platform-view` | Run macOS with the AppKit platform-view path |

Examples:

```bash
dart run tool/run_platform_conformance.dart --device macos
dart run tool/run_platform_conformance.dart --device 4BC64162-0CFF-4C35-B60E-7B4A4EFF0770 --skip-checks
dart run tool/run_platform_conformance.dart --device emulator-5554 --skip-checks
dart run tool/run_platform_conformance.dart --device linux --skip-checks
dart run tool/run_platform_conformance.dart --device windows --skip-checks
```

Use `flutter devices` to list available device IDs.

---

## Documentation

Additional documentation lives in the [`docs/`](docs/) directory:

| File | Description |
|---|---|
| [architecture.md](docs/architecture.md) | Package layout and federated structure |
| [capability_model.md](docs/capability_model.md) | Capability checklist and current enforcement status |
| [quick_start.md](docs/quick_start.md) | Minimal getting-started guide |
| [loading.md](docs/loading.md) | Content loading API details |
| [security.md](docs/security.md) | Security defaults and guidance |
| [platform_matrix.md](docs/platform_matrix.md) | Per-platform capability matrix |
| [email_html_usage.md](docs/email_html_usage.md) | Email HTML rendering guide |
| [migration.md](docs/migration.md) | Migration from `webview_flutter` |

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).

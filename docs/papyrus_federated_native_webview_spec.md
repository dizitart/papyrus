# Papyrus: Federated Native System WebView for Flutter

**Package name:** `papyrus`  
**Package type:** Generic Flutter federated plugin  
**Primary role:** Cross-platform native system WebView abstraction for Flutter  
**Email HTML support:** Supported through explicit configuration profiles and resource APIs, not as the package identity  
**Target platforms:** Android, iOS, macOS, Windows, Linux  
**Document version:** 1.0  
**Status:** Implementation-ready open-source package specification  

---

## 1. Executive Summary

`papyrus` is a generic, production-grade Flutter federated plugin that exposes a stable, extensible, and policy-driven native system WebView API across Android, iOS, macOS, Windows, and Linux.

The package is not an email renderer by name, scope, or branding. It is a general-purpose embedded web content viewer suitable for documentation pages, help centers, controlled HTML previews, legal documents, marketing content, local HTML bundles, offline content, and sanitized email HTML rendering.

The design goal is to provide a high-reliability native WebView layer with a consistent Flutter-facing API while still exposing enough platform capability to support demanding use cases such as professional email HTML display.

---

## 2. Product Positioning

### 2.1 What Papyrus Is

Papyrus is:

- A generic Flutter widget and controller API for native system WebViews.
- A federated plugin with platform-specific implementations.
- A policy-driven WebView runtime for loading HTML, URLs, files, and virtual resources.
- A secure-by-default WebView wrapper that can be configured for strict or permissive use cases.
- A bridge layer that normalizes navigation, resource loading, sizing, events, messages, downloads, permissions, and errors.
- A foundation that applications can use to build specialized viewers, including an email HTML viewer.

### 2.2 What Papyrus Is Not

Papyrus is not:

- An email client.
- A MIME parser.
- An HTML sanitizer.
- A CSS layout engine.
- A replacement for Chromium, WebKit, or WebView2.
- A guarantee of pixel-identical rendering across different browser engines.
- A JavaScript application framework.
- A browser application with tabs, history UI, bookmarks, address bar, or browser chrome.

---

## 3. Package Goals

Papyrus must provide:

1. A clean Flutter widget API for displaying native WebViews.
2. A controller API for programmatic loading, navigation, script injection, reload, stop, print, snapshot, and state query operations.
3. Configurable runtime policies for JavaScript, navigation, storage, mixed content, remote resources, local resources, media, downloads, popups, file access, clipboard, zoom, and permissions.
4. A virtual-resource system for serving local app-controlled content into the WebView.
5. Deterministic event streams for load lifecycle, errors, progress, title changes, URL changes, console messages, navigation requests, resource requests, download requests, permission requests, and size changes.
6. Native system WebView implementations for all target platforms.
7. Extension hooks for specialized use cases such as sanitized email HTML rendering.
8. A conformance test suite and example app covering all supported platforms.

---

## 4. Design Principle

Papyrus must expose a **generic WebView capability model** while allowing callers to configure strict profiles for special domains.

Email rendering must be supported through:

- Strict security profiles.
- Inline HTML loading.
- Local resource mapping for CID-style resources.
- Remote resource blocking.
- Navigation interception.
- Dynamic height measurement.
- Dark-mode control.
- Print/snapshot support.
- Deterministic load/error reporting.

However, these features must be named generically. For example, Papyrus should expose `VirtualResourceProvider`, not `CidImageProvider`; `PapyrusSecurityProfile.lockedDown()`, not `EmailSecurityProfile` as the only option.

---

## 5. Federated Package Structure

The repository must use Flutter federated plugin architecture.

```text
papyrus/
  packages/
    papyrus/                         # Public Flutter package
    papyrus_platform_interface/      # Shared platform contract
    papyrus_android/                 # Android implementation
    papyrus_ios/                     # iOS implementation
    papyrus_macos/                   # macOS implementation
    papyrus_windows/                 # Windows implementation
    papyrus_linux/                   # Linux implementation
  examples/
    papyrus_example/                 # Full demo app
  test/
    golden/
    conformance/
  docs/
    architecture.md
    security.md
    email_html_usage.md
    platform_matrix.md
    migration.md
```

### 5.1 Pub Packages

| Package | Purpose |
|---|---|
| `papyrus` | Main Flutter API consumed by application developers. |
| `papyrus_platform_interface` | Platform interface, data models, method-channel contracts, test mocks. |
| `papyrus_android` | Android System WebView implementation. |
| `papyrus_ios` | iOS `WKWebView` implementation. |
| `papyrus_macos` | macOS `WKWebView` implementation. |
| `papyrus_windows` | Windows WebView2 implementation. |
| `papyrus_linux` | Linux WebKitGTK implementation. |

---

## 6. Supported Native Engines

| Platform | Native engine | Minimum target |
|---|---|---|
| Android | Android System WebView / Chromium WebView | Android 8.0+ recommended |
| iOS | `WKWebView` | iOS 13+ recommended |
| macOS | `WKWebView` | macOS 11+ recommended |
| Windows | Microsoft Edge WebView2 Runtime | Windows 10+ recommended |
| Linux | WebKitGTK | Ubuntu 22.04+ / equivalent distro support recommended |

### 6.1 Engine Dependency Policy

Papyrus must not bundle Chromium or a custom browser engine. It must use native system WebView engines.

Rationale:

- Smaller application binary size.
- Better OS integration.
- Native accessibility behavior.
- Native GPU/text rendering.
- Better maintenance profile.
- No custom browser security patch burden.

---

## 7. Core Public API

### 7.1 Widget API

```dart
class PapyrusView extends StatefulWidget {
  const PapyrusView({
    super.key,
    required this.controller,
    this.initialRequest,
    this.configuration = const PapyrusConfiguration(),
    this.gestureRecognizers,
    this.onCreated,
    this.onPageStarted,
    this.onPageFinished,
    this.onProgressChanged,
    this.onNavigationRequest,
    this.onResourceRequest,
    this.onDownloadRequest,
    this.onPermissionRequest,
    this.onConsoleMessage,
    this.onWebMessage,
    this.onError,
    this.onContentSizeChanged,
  });

  final PapyrusController controller;
  final PapyrusLoadRequest? initialRequest;
  final PapyrusConfiguration configuration;

  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  final ValueChanged<PapyrusController>? onCreated;
  final ValueChanged<PapyrusPageStartedEvent>? onPageStarted;
  final ValueChanged<PapyrusPageFinishedEvent>? onPageFinished;
  final ValueChanged<PapyrusProgressEvent>? onProgressChanged;
  final Future<PapyrusNavigationDecision> Function(PapyrusNavigationRequest)? onNavigationRequest;
  final Future<PapyrusResourceDecision> Function(PapyrusResourceRequest)? onResourceRequest;
  final Future<PapyrusDownloadDecision> Function(PapyrusDownloadRequest)? onDownloadRequest;
  final Future<PapyrusPermissionDecision> Function(PapyrusPermissionRequest)? onPermissionRequest;
  final ValueChanged<PapyrusConsoleMessage>? onConsoleMessage;
  final ValueChanged<PapyrusWebMessage>? onWebMessage;
  final ValueChanged<PapyrusErrorEvent>? onError;
  final ValueChanged<PapyrusContentSize>? onContentSizeChanged;

  @override
  State<PapyrusView> createState() => _PapyrusViewState();
}
```

### 7.2 Controller API

```dart
abstract class PapyrusController {
  Future<void> load(PapyrusLoadRequest request);
  Future<void> loadHtmlString(
    String html, {
    Uri? baseUri,
    PapyrusContentMetadata? metadata,
  });
  Future<void> loadUri(Uri uri, {Map<String, String>? headers});
  Future<void> loadFile(String absolutePath);
  Future<void> reload();
  Future<void> stopLoading();

  Future<bool> canGoBack();
  Future<bool> canGoForward();
  Future<void> goBack();
  Future<void> goForward();

  Future<Uri?> currentUri();
  Future<String?> title();
  Future<double> estimatedProgress();

  Future<Object?> evaluateJavaScript(String source);
  Future<void> addJavaScriptChannel(String name);
  Future<void> removeJavaScriptChannel(String name);

  Future<PapyrusContentSize> getContentSize();
  Future<Uint8List> captureSnapshot({PapyrusSnapshotOptions? options});
  Future<void> printDocument({PapyrusPrintOptions? options});

  Future<void> clearCache();
  Future<void> clearStorage(PapyrusStorageClearOptions options);
  Future<void> dispose();
}
```

### 7.3 Load Request Model

```dart
sealed class PapyrusLoadRequest {
  const PapyrusLoadRequest();
}

class PapyrusHtmlRequest extends PapyrusLoadRequest {
  const PapyrusHtmlRequest({
    required this.html,
    this.baseUri,
    this.metadata,
    this.virtualResources = const [],
  });

  final String html;
  final Uri? baseUri;
  final PapyrusContentMetadata? metadata;
  final List<PapyrusVirtualResource> virtualResources;
}

class PapyrusUriRequest extends PapyrusLoadRequest {
  const PapyrusUriRequest({
    required this.uri,
    this.headers = const {},
  });

  final Uri uri;
  final Map<String, String> headers;
}

class PapyrusFileRequest extends PapyrusLoadRequest {
  const PapyrusFileRequest({required this.absolutePath});
  final String absolutePath;
}

class PapyrusDataRequest extends PapyrusLoadRequest {
  const PapyrusDataRequest({
    required this.bytes,
    required this.mimeType,
    this.encoding,
    this.baseUri,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? encoding;
  final Uri? baseUri;
}
```

---

## 8. Configuration API

```dart
class PapyrusConfiguration {
  const PapyrusConfiguration({
    this.security = const PapyrusSecurityPolicy(),
    this.navigation = const PapyrusNavigationPolicy(),
    this.resources = const PapyrusResourcePolicy(),
    this.javascript = const PapyrusJavaScriptPolicy(),
    this.storage = const PapyrusStoragePolicy(),
    this.media = const PapyrusMediaPolicy(),
    this.display = const PapyrusDisplayPolicy(),
    this.accessibility = const PapyrusAccessibilityPolicy(),
    this.platform = const PapyrusPlatformOptions(),
  });

  final PapyrusSecurityPolicy security;
  final PapyrusNavigationPolicy navigation;
  final PapyrusResourcePolicy resources;
  final PapyrusJavaScriptPolicy javascript;
  final PapyrusStoragePolicy storage;
  final PapyrusMediaPolicy media;
  final PapyrusDisplayPolicy display;
  final PapyrusAccessibilityPolicy accessibility;
  final PapyrusPlatformOptions platform;
}
```

### 8.1 Preset Profiles

Papyrus must ship with built-in generic profiles.

```dart
class PapyrusProfiles {
  static PapyrusConfiguration lockedDown();
  static PapyrusConfiguration documentViewer();
  static PapyrusConfiguration trustedAppContent();
  static PapyrusConfiguration browserLike();
  static PapyrusConfiguration emailHtmlViewer();
}
```

| Profile | Use case | JavaScript | Remote resources | Navigation | Storage |
|---|---|---:|---:|---:|---:|
| `lockedDown()` | Untrusted static HTML | Off | Blocked | External only | Off |
| `documentViewer()` | Legal/help/docs HTML | Off by default | Configurable | Intercepted | Minimal |
| `trustedAppContent()` | App-owned HTML UI | Optional | Allowed by allowlist | Controlled | Isolated |
| `browserLike()` | General web pages | On | Allowed | Normal/interceptable | Allowed |
| `emailHtmlViewer()` | Sanitized email HTML | Off | Blocked by default | External only | Off |

Important: `emailHtmlViewer()` is a convenience profile only. Papyrus remains a generic WebView package.

---

## 9. Security Policy

```dart
class PapyrusSecurityPolicy {
  const PapyrusSecurityPolicy({
    this.allowJavaScript = false,
    this.allowInlineMediaPlayback = false,
    this.allowFileAccess = false,
    this.allowUniversalAccessFromFileUrls = false,
    this.allowPopups = false,
    this.allowMixedContent = false,
    this.allowClipboardRead = false,
    this.allowClipboardWrite = false,
    this.allowGeolocation = false,
    this.allowCamera = false,
    this.allowMicrophone = false,
    this.allowProtectedMedia = false,
    this.enableContentIsolation = true,
    this.contentSecurityPolicy,
  });

  final bool allowJavaScript;
  final bool allowInlineMediaPlayback;
  final bool allowFileAccess;
  final bool allowUniversalAccessFromFileUrls;
  final bool allowPopups;
  final bool allowMixedContent;
  final bool allowClipboardRead;
  final bool allowClipboardWrite;
  final bool allowGeolocation;
  final bool allowCamera;
  final bool allowMicrophone;
  final bool allowProtectedMedia;
  final bool enableContentIsolation;
  final String? contentSecurityPolicy;
}
```

### 9.1 Default Security Behavior

The default configuration must be conservative:

- JavaScript disabled.
- Popups disabled.
- File access disabled.
- Universal file URL access disabled.
- Geolocation/camera/microphone disabled.
- Mixed content blocked where platform supports it.
- Navigation intercepted.
- Download requests surfaced to host app instead of automatically executed.
- Remote resources configurable, but not silently granted in locked-down mode.

### 9.2 Content Security Policy Injection

For HTML string loads, Papyrus may inject a caller-supplied Content Security Policy into the document if the platform cannot enforce equivalent restrictions natively.

The injection layer must be deterministic and documented. It must not claim to sanitize unsafe HTML.

---

## 10. Navigation API

```dart
class PapyrusNavigationRequest {
  const PapyrusNavigationRequest({
    required this.uri,
    required this.isMainFrame,
    required this.navigationType,
    required this.hasUserGesture,
  });

  final Uri uri;
  final bool isMainFrame;
  final PapyrusNavigationType navigationType;
  final bool hasUserGesture;
}

enum PapyrusNavigationType {
  linkClicked,
  formSubmitted,
  backForward,
  reload,
  programmatic,
  other,
}

enum PapyrusNavigationDecision {
  allow,
  block,
  openExternally,
  download,
}
```

### 10.1 Navigation Policy

```dart
class PapyrusNavigationPolicy {
  const PapyrusNavigationPolicy({
    this.defaultDecision = PapyrusNavigationDecision.block,
    this.allowedSchemes = const {'https'},
    this.externalSchemes = const {'http', 'https', 'mailto', 'tel'},
    this.blockedSchemes = const {'javascript', 'data', 'file'},
    this.requireUserGestureForExternalOpen = true,
    this.allowMainFrameNavigation = false,
    this.allowSubFrameNavigation = false,
  });

  final PapyrusNavigationDecision defaultDecision;
  final Set<String> allowedSchemes;
  final Set<String> externalSchemes;
  final Set<String> blockedSchemes;
  final bool requireUserGestureForExternalOpen;
  final bool allowMainFrameNavigation;
  final bool allowSubFrameNavigation;
}
```

### 10.2 Email Viewer Mapping

A mail app using Papyrus should generally configure:

- Main frame navigation blocked.
- Links opened externally only after explicit user gesture.
- `javascript:` and `data:` navigation blocked.
- `mailto:` passed back to host app or opened externally based on app policy.
- No automatic downloads.

---

## 11. Resource Loading API

Papyrus must expose resource interception as a first-class capability.

```dart
class PapyrusResourceRequest {
  const PapyrusResourceRequest({
    required this.uri,
    required this.method,
    required this.headers,
    required this.resourceType,
    required this.isMainFrame,
  });

  final Uri uri;
  final String method;
  final Map<String, String> headers;
  final PapyrusResourceType resourceType;
  final bool isMainFrame;
}

enum PapyrusResourceType {
  document,
  stylesheet,
  image,
  font,
  script,
  xhr,
  media,
  iframe,
  other,
}

sealed class PapyrusResourceDecision {
  const PapyrusResourceDecision();
}

class PapyrusAllowResource extends PapyrusResourceDecision {
  const PapyrusAllowResource();
}

class PapyrusBlockResource extends PapyrusResourceDecision {
  const PapyrusBlockResource();
}

class PapyrusRespondWithResource extends PapyrusResourceDecision {
  const PapyrusRespondWithResource(this.response);
  final PapyrusResourceResponse response;
}
```

### 11.1 Resource Policy

```dart
class PapyrusResourcePolicy {
  const PapyrusResourcePolicy({
    this.remoteResources = PapyrusRemoteResourceMode.block,
    this.allowedHosts = const {},
    this.allowedSchemes = const {'https'},
    this.blockedResourceTypes = const {},
    this.virtualResourceOrigin,
    this.enableRequestInterception = true,
  });

  final PapyrusRemoteResourceMode remoteResources;
  final Set<String> allowedHosts;
  final Set<String> allowedSchemes;
  final Set<PapyrusResourceType> blockedResourceTypes;
  final Uri? virtualResourceOrigin;
  final bool enableRequestInterception;
}

enum PapyrusRemoteResourceMode {
  block,
  allowAll,
  allowByHost,
  askHostApp,
}
```

### 11.2 Virtual Resource API

Papyrus must support app-owned virtual resources.

```dart
class PapyrusVirtualResource {
  const PapyrusVirtualResource({
    required this.uri,
    required this.bytes,
    required this.mimeType,
    this.headers = const {},
  });

  final Uri uri;
  final Uint8List bytes;
  final String mimeType;
  final Map<String, String> headers;
}

abstract class PapyrusVirtualResourceProvider {
  Future<PapyrusResourceResponse?> resolve(PapyrusResourceRequest request);
}
```

This is the generic mechanism that enables email clients to serve inline attachments, CID images, locally cached images, generated CSS, or app-packaged assets without exposing arbitrary file access to the WebView.

---

## 12. JavaScript API

JavaScript must be disabled by default.

```dart
class PapyrusJavaScriptPolicy {
  const PapyrusJavaScriptPolicy({
    this.mode = PapyrusJavaScriptMode.disabled,
    this.allowedChannels = const {},
    this.allowUserScripts = false,
    this.injectedScripts = const [],
  });

  final PapyrusJavaScriptMode mode;
  final Set<String> allowedChannels;
  final bool allowUserScripts;
  final List<PapyrusUserScript> injectedScripts;
}

enum PapyrusJavaScriptMode {
  disabled,
  restricted,
  unrestricted,
}
```

### 12.1 Internal Measurement Scripts

Papyrus may require internal scripts to measure document height or observe layout changes. These must be separated from caller-controlled JavaScript.

```dart
class PapyrusDisplayPolicy {
  const PapyrusDisplayPolicy({
    this.autoHeight = false,
    this.minimumHeight,
    this.maximumHeight,
    this.zoomEnabled = true,
    this.textZoom = 1.0,
    this.backgroundColor,
    this.darkMode = PapyrusDarkMode.system,
    this.viewport = const PapyrusViewportPolicy(),
    this.measurement = const PapyrusMeasurementPolicy(),
  });

  final bool autoHeight;
  final double? minimumHeight;
  final double? maximumHeight;
  final bool zoomEnabled;
  final double textZoom;
  final Color? backgroundColor;
  final PapyrusDarkMode darkMode;
  final PapyrusViewportPolicy viewport;
  final PapyrusMeasurementPolicy measurement;
}
```

Internal measurement scripts must not enable arbitrary page JavaScript when `PapyrusJavaScriptMode.disabled` is selected. If a platform cannot measure content size without JavaScript, Papyrus must document this limitation and use a private, isolated measurement bridge where possible.

---

## 13. Storage and Isolation

```dart
class PapyrusStoragePolicy {
  const PapyrusStoragePolicy({
    this.cookies = PapyrusCookiePolicy.block,
    this.localStorage = PapyrusStorageMode.disabled,
    this.cache = PapyrusCacheMode.defaultMode,
    this.ephemeral = true,
    this.partitionId,
  });

  final PapyrusCookiePolicy cookies;
  final PapyrusStorageMode localStorage;
  final PapyrusCacheMode cache;
  final bool ephemeral;
  final String? partitionId;
}

enum PapyrusCookiePolicy { block, allow, allowByHost }
enum PapyrusStorageMode { disabled, enabled }
enum PapyrusCacheMode { defaultMode, noCache, cacheOnly }
```

For locked-down and email-style rendering, the recommended behavior is ephemeral storage with cookies and local storage disabled.

---

## 14. Media, Permissions, Downloads

### 14.1 Media Policy

```dart
class PapyrusMediaPolicy {
  const PapyrusMediaPolicy({
    this.autoPlay = false,
    this.inlinePlayback = false,
    this.requireUserGesture = true,
    this.allowFullscreen = false,
  });

  final bool autoPlay;
  final bool inlinePlayback;
  final bool requireUserGesture;
  final bool allowFullscreen;
}
```

### 14.2 Permission Requests

Papyrus must not silently grant platform permissions.

```dart
class PapyrusPermissionRequest {
  const PapyrusPermissionRequest({
    required this.uri,
    required this.permissions,
  });

  final Uri uri;
  final Set<PapyrusPermissionType> permissions;
}

enum PapyrusPermissionType {
  camera,
  microphone,
  geolocation,
  notifications,
  clipboardRead,
  clipboardWrite,
  protectedMedia,
  fileChooser,
}

enum PapyrusPermissionDecision {
  grant,
  deny,
  promptHostApp,
}
```

### 14.3 Downloads

```dart
class PapyrusDownloadRequest {
  const PapyrusDownloadRequest({
    required this.uri,
    this.mimeType,
    this.suggestedFilename,
    this.contentLength,
  });

  final Uri uri;
  final String? mimeType;
  final String? suggestedFilename;
  final int? contentLength;
}

enum PapyrusDownloadDecision {
  block,
  allowSystemDownload,
  handToHostApp,
}
```

---

## 15. Event Model

Papyrus must expose both callback-style and stream-style APIs.

```dart
abstract class PapyrusEvent {}

class PapyrusPageStartedEvent extends PapyrusEvent {
  final Uri? uri;
}

class PapyrusPageFinishedEvent extends PapyrusEvent {
  final Uri? uri;
}

class PapyrusProgressEvent extends PapyrusEvent {
  final double progress;
}

class PapyrusErrorEvent extends PapyrusEvent {
  final PapyrusErrorCode code;
  final String message;
  final Uri? uri;
  final bool isMainFrame;
}

class PapyrusContentSizeChangedEvent extends PapyrusEvent {
  final PapyrusContentSize size;
}
```

### 15.1 Error Codes

```dart
enum PapyrusErrorCode {
  unknown,
  navigationBlocked,
  resourceBlocked,
  networkFailed,
  sslFailed,
  timeout,
  rendererCrashed,
  unsupportedPlatformFeature,
  invalidLoadRequest,
  webViewUnavailable,
}
```

---

## 16. Platform-Specific Implementation Requirements

### 16.1 Android

Implementation must use Android System WebView.

Requirements:

- Use Hybrid Composition by default for modern Flutter.
- Disable JavaScript unless enabled.
- Configure `WebSettings` based on policy.
- Intercept navigation via `WebViewClient`.
- Intercept resources via `shouldInterceptRequest` where supported.
- Surface console logs only when configured.
- Handle renderer process crashes via `onRenderProcessGone`.
- Block mixed content unless enabled.
- Disable file access by default.
- Support dark mode where available.

### 16.2 iOS

Implementation must use `WKWebView`.

Requirements:

- Use `WKWebViewConfiguration` per Papyrus configuration.
- Use non-persistent data store for ephemeral mode.
- Disable JavaScript where supported by platform APIs.
- Use `WKNavigationDelegate` for navigation decisions.
- Use `WKURLSchemeHandler` for virtual resources where applicable.
- Surface content size changes through scroll view observation and/or measurement bridge.
- Avoid granting arbitrary file access.

### 16.3 macOS

Implementation must use `WKWebView`.

Requirements are aligned with iOS, with macOS-specific handling for windowing, context menus, print, keyboard, accessibility, and scroll behavior.

### 16.4 Windows

Implementation must use WebView2.

Requirements:

- Detect and report missing WebView2 Runtime clearly.
- Use a configurable user data folder or ephemeral equivalent where possible.
- Use `CoreWebView2` settings for JavaScript, dialogs, status bar, dev tools, host objects, and default script dialogs.
- Intercept navigation and web resource requests.
- Map virtual resources through WebView2 request interception.
- Surface process failure events.

### 16.5 Linux

Implementation must use WebKitGTK.

Requirements:

- Document required system packages.
- Configure WebKit settings according to Papyrus policy.
- Support navigation interception.
- Support resource interception where feasible.
- Provide clear feature parity notes for APIs that WebKitGTK cannot support consistently.

---

## 17. Email HTML Viewer Use Case

Papyrus must support professional email HTML viewing without becoming email-specific.

### 17.1 Expected Input from Email Pipeline

The email/MIME pipeline should produce:

```dart
class PreparedEmailHtml {
  final String sanitizedHtml;
  final Uri baseUri;
  final List<PapyrusVirtualResource> inlineResources;
  final Map<String, String> metadata;
}
```

Papyrus does not create this object. The mail application creates it and then loads it into Papyrus.

### 17.2 Recommended Email Configuration

```dart
final config = PapyrusProfiles.emailHtmlViewer().copyWith(
  display: const PapyrusDisplayPolicy(
    autoHeight: true,
    zoomEnabled: true,
    darkMode: PapyrusDarkMode.system,
  ),
  resources: PapyrusResourcePolicy(
    remoteResources: PapyrusRemoteResourceMode.block,
    virtualResourceOrigin: Uri.parse('papyrus-resource://email.local/'),
  ),
  navigation: const PapyrusNavigationPolicy(
    defaultDecision: PapyrusNavigationDecision.openExternally,
    requireUserGestureForExternalOpen: true,
    allowMainFrameNavigation: false,
  ),
);
```

### 17.3 Recommended Email Loading Pattern

```dart
await controller.load(
  PapyrusHtmlRequest(
    html: preparedEmail.sanitizedHtml,
    baseUri: preparedEmail.baseUri,
    virtualResources: preparedEmail.inlineResources,
    metadata: PapyrusContentMetadata(
      contentType: 'text/html',
      source: 'email',
      identifier: messageId,
    ),
  ),
);
```

### 17.4 Email-Specific Requirements Supported by Generic APIs

| Email requirement | Papyrus generic feature |
|---|---|
| Render sanitized HTML body | `PapyrusHtmlRequest` |
| Display inline CID images | `PapyrusVirtualResource` |
| Block tracking pixels | `PapyrusResourcePolicy.remoteResources = block` |
| User-controlled remote image loading | `remoteResources = askHostApp` |
| Open links externally | `PapyrusNavigationPolicy` |
| Disable scripts | `PapyrusJavaScriptPolicy.disabled` |
| Auto-size message body | `PapyrusDisplayPolicy.autoHeight` |
| Dark/light mode handling | `PapyrusDisplayPolicy.darkMode` |
| Print email | `controller.printDocument()` |
| Screenshot/regression testing | `controller.captureSnapshot()` |

---

## 18. Public Extension Points

Papyrus must be extensible without requiring forks.

### 18.1 Resource Providers

Applications may register one or more resource providers.

```dart
class PapyrusResourceRegistry {
  void register(PapyrusVirtualResourceProvider provider);
  void unregister(PapyrusVirtualResourceProvider provider);
}
```

### 18.2 Policy Resolvers

```dart
typedef PapyrusNavigationResolver = Future<PapyrusNavigationDecision> Function(
  PapyrusNavigationRequest request,
);

typedef PapyrusResourceResolver = Future<PapyrusResourceDecision> Function(
  PapyrusResourceRequest request,
);
```

### 18.3 Platform Capability Query

```dart
class PapyrusPlatformCapabilities {
  final bool supportsResourceInterception;
  final bool supportsVirtualSchemes;
  final bool supportsEphemeralStorage;
  final bool supportsPrint;
  final bool supportsSnapshot;
  final bool supportsAutoHeight;
  final bool supportsDarkMode;
  final bool supportsDownloadInterception;
  final bool supportsPermissionInterception;
}

Future<PapyrusPlatformCapabilities> getPapyrusCapabilities();
```

---

## 19. Rendering Correctness Position

Papyrus must be honest about rendering correctness.

It can promise:

- Native browser-engine rendering fidelity on each platform.
- Stable Flutter API behavior.
- Correct application of configured policies.
- Deterministic loading and event behavior where platform APIs allow.
- Best-effort cross-platform consistency.

It must not promise:

- Pixel-perfect equality across Android WebView, WKWebView, WebView2, and WebKitGTK.
- Pixel-perfect equality with Gmail, Outlook, Apple Mail, or Yahoo Mail.
- Correct display of malicious or unsanitized HTML.
- Rendering parity for HTML/CSS features unsupported by the underlying native engine.

For email use cases, correctness must be achieved by combining:

1. A robust MIME-to-sanitized-HTML pipeline outside Papyrus.
2. Conservative Papyrus policies.
3. Native browser-engine rendering.
4. Snapshot-based regression tests against representative email fixtures.

---

## 20. Testing Strategy

### 20.1 Unit Tests

Must cover:

- Configuration defaults.
- Policy serialization.
- Load request validation.
- Navigation decisions.
- Resource decisions.
- Virtual resource lookup.
- Error mapping.
- Capability mapping.

### 20.2 Platform Integration Tests

Must cover each platform:

- Load HTML string.
- Load remote URL.
- Load local file when enabled.
- Block local file when disabled.
- Block JavaScript when disabled.
- Execute JavaScript when enabled.
- Intercept link clicks.
- Intercept resource requests.
- Serve virtual images/CSS/fonts.
- Auto-height measurement.
- Snapshot capture.
- Print support or graceful unsupported error.
- Renderer crash or WebView unavailable handling where testable.

### 20.3 Email Scenario Tests

These tests live in Papyrus as generic examples and conformance tests, not as mail-client business logic.

Fixtures should include:

- Table-heavy HTML.
- Nested tables.
- Inline CSS.
- External CSS blocked.
- CID-style virtual images.
- Tracking pixel blocked.
- Large newsletter.
- Transactional receipt.
- RTL content.
- CJK content.
- Emoji and web-safe fonts.
- Dark-mode sensitive HTML.
- Long unbroken URLs.
- Malformed but browser-recoverable HTML.

### 20.4 Golden/Screenshot Tests

Papyrus should provide a test harness that captures platform screenshots and compares them against per-platform baselines.

Cross-platform screenshots must not be compared against a single universal baseline because native engines differ.

---

## 21. Documentation Requirements

The package documentation must include:

1. Quick start.
2. Loading HTML.
3. Loading URLs.
4. Loading local files.
5. Security profiles.
6. Navigation interception.
7. Resource interception.
8. Virtual resources.
9. JavaScript policy.
10. Storage/cookie policy.
11. Auto-height usage.
12. Printing and snapshotting.
13. Platform capability matrix.
14. Email HTML viewer recipe.
15. Known platform differences.
16. Migration guide from `webview_flutter` and other WebView packages.

---

## 22. Example: Generic Document Viewer

```dart
final controller = PapyrusController.create();

PapyrusView(
  controller: controller,
  configuration: PapyrusProfiles.documentViewer(),
  initialRequest: PapyrusHtmlRequest(
    html: termsAndConditionsHtml,
    baseUri: Uri.parse('https://app.local/docs/'),
  ),
);
```

---

## 23. Example: Trusted App Content

```dart
final config = PapyrusProfiles.trustedAppContent().copyWith(
  javascript: const PapyrusJavaScriptPolicy(
    mode: PapyrusJavaScriptMode.restricted,
    allowedChannels: {'PapyrusHost'},
  ),
);
```

---

## 24. Example: Sanitized Email HTML Viewer

```dart
final controller = PapyrusController.create();

final config = PapyrusProfiles.emailHtmlViewer();

PapyrusView(
  controller: controller,
  configuration: config,
  onNavigationRequest: (request) async {
    if (request.hasUserGesture && request.uri.scheme == 'https') {
      return PapyrusNavigationDecision.openExternally;
    }
    return PapyrusNavigationDecision.block;
  },
  onResourceRequest: (request) async {
    final local = await emailResourceProvider.resolve(request);
    if (local != null) {
      return PapyrusRespondWithResource(local);
    }
    return const PapyrusBlockResource();
  },
  onContentSizeChanged: (size) {
    setState(() => messageBodyHeight = size.height);
  },
);

await controller.load(
  PapyrusHtmlRequest(
    html: sanitizedEmailHtml,
    baseUri: Uri.parse('papyrus-resource://email.local/message/$messageId/'),
    virtualResources: inlineResources,
  ),
);
```

---

## 25. Acceptance Criteria

Papyrus v1.0 is acceptable when:

1. The public Dart API is stable and documented.
2. All platform packages implement the same core load, navigation, resource, error, and event contracts.
3. Android, iOS, macOS, Windows, and Linux examples build and run.
4. JavaScript is disabled by default.
5. Navigation interception works on all platforms.
6. Resource interception works on all platforms where native APIs support it, and unsupported limitations are documented.
7. Virtual resources can be served into loaded HTML.
8. Email-style rendering can block remote resources and serve inline local resources.
9. Auto-height works or gracefully reports unsupported behavior per platform.
10. Missing WebView2 on Windows is reported as a structured error.
11. Linux system dependency requirements are documented.
12. The package includes conformance tests and example recipes.
13. The package does not include MIME parsing, sanitization, mailbox sync, or email-client business logic.

---

## 26. Versioning Policy

Papyrus must follow semantic versioning.

- Patch versions: bug fixes and platform compatibility fixes.
- Minor versions: additive APIs and platform capability expansion.
- Major versions: breaking API changes.

The platform interface package must avoid frequent breaking changes. Platform implementations must declare compatible interface ranges.

---

## 27. Recommended Implementation Phases

### Phase 1: Core API and Android/iOS MVP

- Define `papyrus` and `papyrus_platform_interface`.
- Implement load HTML, load URL, navigation interception, basic errors.
- Implement Android and iOS.
- Ship example app.

### Phase 2: Desktop Support

- Implement macOS, Windows, Linux.
- Add capability query API.
- Add WebView2 availability handling.
- Document Linux dependencies.

### Phase 3: Resource and Security Hardening

- Add virtual resources.
- Add resource interception.
- Add storage/cookie policy.
- Add permission/download interception.
- Add strict profiles.

### Phase 4: Professional Viewer Features

- Auto-height.
- Snapshot.
- Print.
- Dark-mode handling.
- Text zoom.
- Accessibility improvements.

### Phase 5: Email HTML Recipe and Conformance Suite

- Add email viewer recipe.
- Add representative email fixtures.
- Add screenshot baselines.
- Add remote-resource blocking tests.
- Add CID/virtual-resource tests.

---

## 28. Relationship With MIME Pipeline Spec

Papyrus must remain independent from the MIME pipeline.

The MIME pipeline package or app layer is responsible for:

- MIME parsing.
- Body part selection.
- Character set decoding.
- CID extraction.
- Attachment extraction.
- HTML sanitization.
- CSS cleanup.
- Link rewriting.
- Tracking protection policy.
- Producing sanitized HTML and virtual resources.

Papyrus is responsible for:

- Displaying prepared content.
- Enforcing WebView runtime policies.
- Loading virtual resources.
- Reporting events/errors.
- Providing a stable cross-platform WebView abstraction.

This separation allows Papyrus to be useful far beyond email while still being strong enough for email rendering.

---

## 29. Final Package Promise

Papyrus should be described publicly as:

> A policy-driven, federated native system WebView for Flutter, designed for secure, extensible, cross-platform rendering of controlled web content.

For email use cases, the recommended positioning is:

> Papyrus can power professional sanitized email HTML viewing when paired with a robust MIME and sanitization pipeline.

This distinction is essential. It lets Papyrus become a generic open-source WebView foundation while still satisfying the strict requirements of production email clients.

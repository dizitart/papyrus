## ADDED Requirements

### Requirement: Android Native WebView
The Android implementation SHALL use Android System WebView, configure `WebSettings` from Papyrus policies, use Hybrid Composition by default for modern Flutter, intercept navigation/resources where supported, surface console logs only when configured, handle renderer crashes, block mixed content unless enabled, disable file access by default, and support dark mode where available.

#### Scenario: Android disables JavaScript by default
- **WHEN** Android loads content with default configuration
- **THEN** the underlying WebView settings disable JavaScript and file access unless explicitly enabled by policy

### Requirement: iOS WKWebView
The iOS implementation SHALL use `WKWebView`, configure `WKWebViewConfiguration` from Papyrus policies, use non-persistent data stores for ephemeral mode, disable JavaScript where supported, use navigation delegates, support virtual resources through URL scheme handling where applicable, report content-size changes, and avoid arbitrary file access.

#### Scenario: iOS ephemeral load
- **WHEN** iOS loads content with ephemeral storage enabled
- **THEN** the underlying WKWebView uses non-persistent storage where supported

### Requirement: macOS WKWebView
The macOS implementation SHALL use `WKWebView` and align with iOS behavior while handling macOS-specific windowing, context menus, print, keyboard, accessibility, and scroll behavior.

#### Scenario: macOS print request
- **WHEN** the host requests document printing on macOS
- **THEN** Papyrus uses WKWebView print support or returns a structured unsupported-feature error

### Requirement: Windows WebView2
The Windows implementation SHALL use Microsoft Edge WebView2, clearly detect and report missing WebView2 Runtime, configure user data or ephemeral behavior where possible, apply CoreWebView2 settings from policy, intercept navigation and web resources, map virtual resources through request interception, and surface process failure events.

#### Scenario: Missing WebView2 runtime
- **WHEN** WebView2 Runtime is not available
- **THEN** Papyrus reports `webViewUnavailable` with clear diagnostics

### Requirement: Linux WebKitGTK
The Linux implementation SHALL use WebKitGTK, document required system packages, configure WebKit settings from Papyrus policy, support navigation interception, support resource interception where feasible, and document feature parity limits.

#### Scenario: Linux dependency documentation
- **WHEN** Linux support is documented
- **THEN** the documentation lists required WebKitGTK/system packages and known capability differences

### Requirement: No Bundled Browser Engine
Papyrus SHALL NOT bundle Chromium or a custom browser engine and SHALL rely on native system WebView engines for rendering, accessibility, GPU/text behavior, and security update cadence.

#### Scenario: Package build artifacts are inspected
- **WHEN** Papyrus packages are built
- **THEN** they do not include a bundled Chromium or custom browser runtime


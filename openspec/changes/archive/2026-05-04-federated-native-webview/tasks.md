## 1. Workspace and Package Structure

- [x] 1.1 Create the Flutter federated package tree for `papyrus`, `papyrus_platform_interface`, `papyrus_android`, `papyrus_ios`, `papyrus_macos`, `papyrus_windows`, and `papyrus_linux`.
- [x] 1.2 Create `examples/papyrus_example`, `docs`, `test/golden`, and `test/conformance` directories with package-level README placeholders.
- [x] 1.3 Configure shared analysis, formatting, package metadata, platform registration, and local path dependencies across all packages.
- [x] 1.4 Add initial CI/test commands for package analysis, unit tests, and platform-gated integration tests.

## 2. Shared Platform Interface

- [x] 2.1 Define platform interface classes, method contracts, registration API, and mockable test surface in `papyrus_platform_interface`.
- [x] 2.2 Define shared load request, metadata, configuration, policy, profile, event, error, resource, download, permission, snapshot, print, and capability data models.
- [x] 2.3 Add serialization and validation helpers for platform-channel payloads.
- [x] 2.4 Add unit tests for model equality, validation, serialization, default values, and platform interface mocking.

## 3. Public Flutter API

- [x] 3.1 Implement `PapyrusView` with controller binding, initial request loading, configuration delivery, gesture recognizers, callbacks, and stream subscription wiring.
- [x] 3.2 Implement `PapyrusController` operations for load, reload, stop, back/forward, state query, JavaScript operations, content size, snapshot, print, cache/storage clearing, and dispose.
- [x] 3.3 Implement `PapyrusProfiles.lockedDown`, `documentViewer`, `trustedAppContent`, `browserLike`, and `emailHtmlViewer`.
- [x] 3.4 Implement public extension points for virtual resource providers, resource registry, navigation resolvers, resource resolvers, and capability queries.
- [x] 3.5 Add public package unit tests for controller delegation, view lifecycle wiring, profile defaults, and unsupported-feature behavior.

## 4. Security and Policy Enforcement

- [x] 4.1 Implement shared validation for conservative defaults: JavaScript off, popups off, file access off, universal file URL access off, no silent permissions, intercepted navigation, and host-surfaced downloads.
- [x] 4.2 Implement navigation policy resolution for allowed, blocked, external, download, user-gesture, main-frame, and sub-frame decisions.
- [x] 4.3 Implement JavaScript policy handling for disabled, restricted, unrestricted, channels, user scripts, and injected scripts.
- [x] 4.4 Implement storage, cookie, cache, ephemeral, and partition policy mapping.
- [x] 4.5 Implement media, permission, download, mixed-content, clipboard, and file-access policy mapping.
- [x] 4.6 Implement deterministic content security policy injection for HTML string loads and document its non-sanitization boundary.

## 5. Android and iOS MVP

- [x] 5.1 Implement Android System WebView creation with policy-backed `WebSettings`, Hybrid Composition defaults, load HTML, load URI, navigation interception, progress, title, URL, and basic error events.
- [x] 5.2 Implement Android blocking for default JavaScript, file access, mixed content, popups, permissions, and downloads.
- [x] 5.3 Implement Android renderer crash handling, console message surfacing, resource interception where supported, and capability reporting.
- [x] 5.4 Implement iOS `WKWebView` creation with policy-backed `WKWebViewConfiguration`, non-persistent storage where configured, load HTML, load URI, navigation delegates, progress, title, URL, and basic error events.
- [x] 5.5 Implement iOS JavaScript disabling where supported, virtual scheme handling where applicable, file-access constraints, and capability reporting.
- [x] 5.6 Add Android and iOS integration tests for HTML load, URL load, JavaScript disabled/enabled, link interception, local file blocking, basic errors, and capabilities.

## 6. Desktop Platform Implementations

- [x] 6.1 Implement macOS `WKWebView` behavior aligned with iOS plus macOS-specific print, keyboard, accessibility, context menu, scroll, and capability behavior.
- [x] 6.2 Implement Windows WebView2 creation, missing-runtime detection, user data folder or ephemeral equivalent, settings mapping, navigation/resource interception, virtual resources, and process failure events.
- [x] 6.3 Implement Linux WebKitGTK creation, settings mapping, navigation interception, feasible resource interception, capability reporting, and dependency diagnostics.
- [x] 6.4 Add desktop integration tests for platform creation, policy mapping, navigation, resource support where feasible, unavailable-runtime behavior, and capability reporting.

## 7. Virtual Resources and Resource Interception

- [x] 7.1 Implement `PapyrusVirtualResource`, `PapyrusResourceResponse`, `PapyrusVirtualResourceProvider`, and `PapyrusResourceRegistry`.
- [x] 7.2 Implement resource policy modes for block, allow all, allow by host, ask host app, allowed schemes, allowed hosts, blocked types, and virtual origins.
- [x] 7.3 Implement host-controlled responses for allow, block, and respond-with-resource decisions across supported platforms.
- [x] 7.4 Add tests for virtual images, virtual CSS/fonts, blocked remote resources, allowed host resources, and provider registration/unregistration.

## 8. Viewer Features

- [x] 8.1 Implement content-size query and change events with native or isolated measurement bridges that do not enable page-authored JavaScript.
- [x] 8.2 Implement auto-height policy behavior with minimum height, maximum height, viewport policy, and unsupported-feature reporting.
- [x] 8.3 Implement snapshot capture with options and structured unsupported-feature errors.
- [x] 8.4 Implement print support with options and structured unsupported-feature errors.
- [x] 8.5 Implement display policies for zoom, text zoom, background color, dark mode, viewport behavior, and accessibility options.
- [x] 8.6 Add tests for auto-height, measurement isolation, snapshot, print, dark mode capability, zoom, and content-size events.

## 9. Documentation and Examples

- [x] 9.1 Write docs for quick start, loading HTML, loading URLs, loading local files, security profiles, navigation interception, resource interception, virtual resources, JavaScript, storage/cookies, auto-height, print, snapshot, and capabilities.
- [x] 9.2 Write `docs/email_html_usage.md` showing sanitized email HTML loading, virtual inline resources, remote-resource blocking, external link handling, auto-height, print, and snapshot.
- [x] 9.3 Write `docs/platform_matrix.md`, `docs/security.md`, `docs/architecture.md`, and `docs/migration.md`.
- [x] 9.4 Build the example app screens for document viewing, trusted app content, URL loading, strict policy behavior, virtual resources, platform capabilities, snapshot/print, and sanitized email HTML.
- [x] 9.5 Document that Papyrus does not parse MIME, sanitize HTML, bundle a browser engine, or promise cross-engine pixel-perfect parity.

## 10. Conformance and Release Readiness

- [x] 10.1 Add conformance fixtures for table-heavy HTML, nested tables, inline CSS, blocked external CSS, virtual images, blocked tracking pixels, newsletters, receipts, RTL, CJK, emoji/web-safe fonts, dark-mode-sensitive HTML, long URLs, and malformed browser-recoverable HTML.
- [x] 10.2 Add per-platform screenshot/golden capture and comparison harnesses with separate baselines for each native engine.
- [x] 10.3 Add acceptance tests covering stable public API documentation, platform contract parity, examples, conservative defaults, navigation interception, resource interception, virtual resources, email-style resource blocking, auto-height or unsupported reporting, WebView2 missing-runtime errors, Linux dependency docs, and exclusion of MIME/sanitization logic.
- [x] 10.4 Run formatting, static analysis, unit tests, platform integration tests available in the local environment, conformance tests, and documentation link checks.
- [x] 10.5 Update package versioning and release notes according to semantic versioning and platform interface compatibility rules.

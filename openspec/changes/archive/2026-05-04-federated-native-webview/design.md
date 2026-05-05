## Context

Papyrus is being specified as a generic Flutter federated plugin that wraps native system WebViews across mobile and desktop platforms. The source requirement, `papyrus_federated_native_webview_spec.md`, explicitly positions Papyrus as a controlled web content viewer rather than an email client, MIME parser, sanitizer, browser shell, or custom HTML/CSS layout engine.

The repository currently contains only OpenSpec configuration and the package specification, so this change establishes the initial implementation contract. The implementation will introduce a federated package layout, a shared platform interface, platform packages for Android/iOS/macOS/Windows/Linux, docs, examples, and test infrastructure.

## Goals / Non-Goals

**Goals:**

- Provide a stable Dart API centered on `PapyrusView`, `PapyrusController`, load requests, configuration policies, events, errors, and capabilities.
- Use native system engines: Android System WebView, WKWebView, WebView2, and WebKitGTK.
- Make the default runtime conservative: JavaScript off, popups off, file access off, permissions denied unless surfaced, intercepted navigation, and host-controlled downloads/resources.
- Support generic controlled-content use cases, including document viewers, app-owned HTML, URL loads, local files when explicitly allowed, virtual resources, print, snapshot, and auto-height.
- Support sanitized email HTML through explicit profiles, resource APIs, and examples while keeping MIME parsing and sanitization outside Papyrus.
- Provide tests, docs, examples, and platform capability reporting so unsupported native features fail predictably.

**Non-Goals:**

- Do not implement an HTML parser, CSS layout engine, sanitizer, MIME parser, mailbox synchronizer, or email client.
- Do not bundle Chromium or any custom browser engine.
- Do not promise pixel-identical rendering across native engines or against Gmail, Outlook, Apple Mail, or other clients.
- Do not silently grant navigation, storage, download, media, file, clipboard, or device permissions.
- Do not build browser chrome such as tabs, address bars, bookmarks, or history UI.

## Decisions

### Use a Flutter Federated Plugin Structure

Papyrus will be implemented as `packages/papyrus`, `packages/papyrus_platform_interface`, and one package per platform implementation, with `examples/papyrus_example`, docs, and tests at the repository level.

Rationale: Flutter federated plugins are the standard way to keep the public API stable while allowing platform implementations to evolve independently. This also lets platforms declare capability gaps without polluting the app-facing API with platform conditionals.

Alternative considered: a single monolithic plugin package. This is simpler initially but makes platform ownership, native dependency management, and interface compatibility harder as desktop support expands.

### Keep the Public API Generic and Policy-Driven

The public API will expose generic load requests, policies, profiles, virtual resources, resource providers, navigation/resource resolvers, events, and capabilities. Email support appears as `PapyrusProfiles.emailHtmlViewer()` and documentation recipes, not as the package identity.

Rationale: The same runtime primitives support documents, help content, legal HTML, app-owned HTML, offline bundles, and sanitized email HTML. Generic naming keeps Papyrus reusable and avoids coupling it to a MIME pipeline.

Alternative considered: an email-first API with `CidImageProvider` or `EmailSecurityProfile`. That would make the first target use case convenient but would incorrectly place email-specific responsibilities inside the WebView layer.

### Enforce Conservative Defaults in Shared Policy Models

The shared configuration model will default to JavaScript disabled, no popups, no file access, no universal file URL access, intercepted navigation, no silent permissions, and blocked or host-controlled risky resource behavior in strict profiles.

Rationale: Native WebViews are powerful embedding surfaces. Papyrus must be safe for controlled HTML by default, especially because email-style content is a supported use case.

Alternative considered: browser-like defaults. This is familiar for URL browsing but unsafe for untrusted or app-controlled HTML and would force every strict caller to remember to disable risky features.

### Route All Platform Behavior Through the Platform Interface

The platform interface will own data models, method contracts, capability reporting, error codes, and mockable test surfaces. Platform packages must translate native APIs into the shared contracts.

Rationale: This creates deterministic Flutter-facing behavior even when native APIs differ. It also gives unit tests a stable boundary for policy serialization, validation, and event mapping.

Alternative considered: direct method-channel definitions in the public package. That shortens the first implementation but increases coupling and makes third-party platform implementations harder.

### Treat Unsupported Features as Structured Capability or Error Results

Features such as print, snapshot, resource interception, ephemeral storage, auto-height, download interception, and permission interception must be discoverable through `PapyrusPlatformCapabilities` and fail with structured `unsupportedPlatformFeature` errors where unavailable.

Rationale: Native engine parity varies substantially, especially on Linux and Windows runtime availability. Apps need predictable behavior rather than silent no-ops.

Alternative considered: best-effort execution without capability reporting. This hides important runtime differences and makes conformance impossible to reason about.

### Separate Internal Measurement From Caller JavaScript

Auto-height and content-size observation may use platform-native mechanisms or private measurement bridges, but enabling measurement must not grant page-authored JavaScript when the caller selected disabled JavaScript.

Rationale: Strict profiles need layout measurement without expanding script execution privileges.

Alternative considered: require JavaScript for auto-height. This would be simpler on some platforms but would make strict document and email profiles less useful.

## Risks / Trade-offs

- Native engine feature gaps -> Report platform capabilities, document limitations, and provide graceful unsupported errors.
- Large public API surface too early -> Keep v1 contracts focused on load, policy, event, resource, capability, snapshot, print, and auto-height primitives from the source spec.
- Security regressions from platform defaults -> Centralize policy defaults in the public package and require platform tests for JavaScript, navigation, resources, file access, permissions, and downloads.
- Cross-platform screenshot instability -> Maintain per-platform baselines instead of a universal visual baseline.
- WebView2 runtime missing on Windows -> Detect at creation time and report `webViewUnavailable` with actionable diagnostics.
- Linux WebKitGTK packaging variance -> Document required system packages and capability differences in the platform matrix.
- Email expectations leaking into core API -> Keep MIME, sanitization, CID extraction, tracking-policy decisions, and mailbox logic outside Papyrus; expose only generic virtual-resource and policy hooks.

## Migration Plan

1. Scaffold the federated package tree and shared platform interface.
2. Implement the public Dart API and policy models with unit coverage before platform packages rely on them.
3. Implement Android and iOS MVP loading, navigation interception, basic errors, and example app.
4. Add desktop platform packages and capability reporting.
5. Add resource interception, virtual resources, strict profiles, storage, downloads, and permissions.
6. Add professional viewer features: auto-height, snapshot, print, dark mode, text zoom, and accessibility behavior.
7. Add email HTML recipe docs, scenario fixtures, and per-platform screenshot/conformance baselines.

Rollback strategy is package-level: each platform package can be held back or marked unsupported through capability reporting while the stable public API and platform interface remain intact.

## Open Questions

- What minimum Flutter/Dart SDK versions should the first published packages declare?
- Should Linux support target only GTK3/WebKit2GTK initially, or also prepare for GTK4/WebKitGTK variants?
- What native test environments will be available in CI for iOS, macOS, Windows WebView2, and Linux WebKitGTK?
- Which snapshot comparison tolerance and storage format should be used for per-platform golden baselines?

## Why

Papyrus needs a clear v1 product contract for becoming a generic Flutter federated native WebView package instead of an email-specific renderer or a custom HTML/CSS engine. This change turns the implementation-ready package specification in `papyrus_federated_native_webview_spec.md` into OpenSpec artifacts that can guide phased implementation, platform work, tests, and documentation.

## What Changes

- Define Papyrus as a policy-driven, federated native system WebView for Flutter across Android, iOS, macOS, Windows, and Linux.
- Introduce the public `papyrus` widget/controller API, platform interface package, and platform implementation package structure.
- Add secure-by-default configuration policies for security, navigation, resources, JavaScript, storage, media, display, accessibility, and platform options.
- Add generic loading APIs for HTML strings, URLs, files, byte data, and app-owned virtual resources.
- Add navigation, resource, download, permission, event, error, snapshot, print, auto-height, and capability-query contracts.
- Add built-in generic profiles, including locked-down, document-viewer, trusted-app-content, browser-like, and email-html-viewer profiles.
- Add platform implementation requirements for Android System WebView, iOS/macOS WKWebView, Windows WebView2, and Linux WebKitGTK.
- Add documentation, examples, conformance tests, platform screenshot baselines, and an email HTML viewer recipe that remains separate from MIME parsing and sanitization.
- Remove any product expectation that Papyrus is a MIME parser, sanitizer, email client, custom CSS layout engine, browser app, or cross-engine pixel-perfect renderer.

## Capabilities

### New Capabilities

- `federated-package-architecture`: Defines the federated Flutter package layout, public package roles, platform implementation packages, and example/docs/test structure.
- `webview-public-api`: Defines `PapyrusView`, `PapyrusController`, load request models, configuration objects, profiles, and extension points.
- `webview-policy-enforcement`: Defines secure defaults and runtime enforcement for JavaScript, navigation, resource loading, storage, media, downloads, permissions, file access, mixed content, popups, clipboard, and content isolation.
- `virtual-resource-loading`: Defines app-owned virtual resources, virtual resource providers, resource interception, and host-controlled resource decisions.
- `webview-events-and-capabilities`: Defines deterministic callbacks/streams, structured errors, content-size reporting, platform capability queries, snapshot, print, and graceful unsupported-feature behavior.
- `native-platform-implementations`: Defines platform-specific behavior for Android System WebView, iOS/macOS WKWebView, Windows WebView2, and Linux WebKitGTK.
- `email-html-viewer-recipe`: Defines the generic APIs and recommended profile needed to support sanitized email HTML viewing without making Papyrus responsible for MIME parsing, sanitization, or mailbox logic.
- `webview-conformance-and-docs`: Defines unit, integration, scenario, screenshot/golden, documentation, example, migration, and platform-matrix requirements.

### Modified Capabilities

- None.

## Impact

- Adds a multi-package Flutter federated plugin structure under `packages/`, with public API, platform interface, Android, iOS, macOS, Windows, and Linux packages.
- Adds native dependencies on Android System WebView, WebKit/WKWebView, Microsoft Edge WebView2 Runtime, and WebKitGTK.
- Adds public Dart API surface for loading, policies, events, errors, virtual resources, platform capabilities, print, snapshot, and auto-height.
- Adds example app, docs, platform capability matrix, migration notes, email HTML usage guide, and conformance fixtures.
- Establishes security-sensitive defaults that affect all load, navigation, resource, storage, JavaScript, permission, and download behavior.

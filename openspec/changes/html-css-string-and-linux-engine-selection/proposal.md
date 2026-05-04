## Why

Papyrus needs a first-class way to load HTML and CSS supplied as separate strings so callers can render generated, sanitized, or templated content without manually assembling a full document. Linux support also needs to respect desktop-environment expectations: KDE-based distributions should be able to use QtWebEngine while GNOME-based distributions continue to use WebKitGTK.

## What Changes

- Add an explicit load path for HTML plus CSS strings, including optional base URI, metadata, virtual resources, CSS media, and policy-aware document composition.
- Preserve existing HTML string loading while adding a safer structured API for callers that maintain HTML body/content and CSS separately.
- Add Linux WebView engine selection for QtWebEngine and WebKitGTK.
- Prefer QtWebEngine on KDE-based Linux environments and WebKitGTK on GNOME-based environments.
- Add explicit Linux engine override/configuration so applications or distributions can force QtWebEngine, force WebKitGTK, or use automatic desktop-environment selection.
- Add capability reporting, dependency diagnostics, documentation, examples, and conformance tests for both Linux engines.
- Add graceful fallback/error behavior when the preferred Linux engine is unavailable.

## Capabilities

### New Capabilities

- `html-css-string-loading`: Defines APIs and behavior for loading HTML and CSS supplied as strings, including deterministic composition, base URI handling, policy application, virtual resource support, and tests.
- `linux-webview-engine-selection`: Defines Linux engine selection between QtWebEngine and WebKitGTK, including KDE/GNOME defaults, explicit overrides, dependency diagnostics, fallback behavior, capabilities, docs, and tests.

### Modified Capabilities

- None.

## Impact

- Extends the public Dart API, platform interface models, controller methods, examples, and documentation.
- Adds Linux implementation scope for QtWebEngine alongside WebKitGTK.
- Adds Linux-native dependency detection and platform capability reporting for both QtWebEngine and WebKitGTK.
- Adds conformance coverage for composed HTML+CSS loads and Linux engine selection behavior.
- Updates platform matrix and Linux setup documentation to explain KDE/QtWebEngine and GNOME/WebKitGTK support.

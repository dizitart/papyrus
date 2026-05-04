## 1. Public API and Shared Models

- [ ] 1.1 Add `PapyrusHtmlCssRequest` to the load request model with HTML, CSS, base URI, metadata, virtual resources, CSS media, and composition options.
- [ ] 1.2 Add `PapyrusController.loadHtmlCssString` as a convenience API that creates and loads `PapyrusHtmlCssRequest`.
- [ ] 1.3 Add Linux engine configuration models for automatic, QtWebEngine, and WebKitGTK selection plus fallback policy.
- [ ] 1.4 Add Linux engine diagnostics and capability fields for selected engine, available engines, attempted engine, missing dependencies, and fallback state.
- [ ] 1.5 Update platform interface serialization and validation for HTML+CSS loads and Linux engine options.

## 2. HTML+CSS Composition

- [ ] 2.1 Implement deterministic composition for fragment HTML by wrapping it in a stable document structure and placing CSS before body content renders.
- [ ] 2.2 Implement deterministic composition for full HTML documents by inserting CSS into the document head with stable ordering.
- [ ] 2.3 Preserve base URI, metadata, virtual resources, CSP handling, navigation policy, resource policy, JavaScript policy, storage policy, and event/error behavior for HTML+CSS loads.
- [ ] 2.4 Document that Papyrus does not sanitize, validate, rewrite, or make unsafe CSS safe.
- [ ] 2.5 Add unit tests for fragment composition, full-document composition, CSS ordering, malformed browser-recoverable markup, base URI handling, CSP placement, and virtual resource references.

## 3. Platform Load Plumbing

- [ ] 3.1 Route `PapyrusHtmlCssRequest` through the same shared platform load path as HTML string requests after deterministic composition.
- [ ] 3.2 Preserve original HTML+CSS request metadata for diagnostics and debugging.
- [ ] 3.3 Add platform interface tests proving HTML+CSS load payloads reach registered mock platform implementations.
- [ ] 3.4 Add integration fixtures that verify rendered CSS from string input on each supported platform available in the test environment.

## 4. Linux Engine Selection

- [ ] 4.1 Implement Linux desktop-environment detection using `XDG_CURRENT_DESKTOP`, `DESKTOP_SESSION`, and related environment signals.
- [ ] 4.2 Select QtWebEngine by default for KDE/Plasma sessions in automatic mode.
- [ ] 4.3 Select WebKitGTK by default for GNOME sessions in automatic mode.
- [ ] 4.4 Honor explicit QtWebEngine and explicit WebKitGTK overrides before automatic detection.
- [ ] 4.5 Implement configurable fallback behavior when the preferred Linux engine is unavailable and another supported engine is installed.
- [ ] 4.6 Report structured errors when fallback is disabled or no supported Linux engine is available.

## 5. Linux Engine Adapters

- [ ] 5.1 Add or extend the Linux platform package with an internal WebKitGTK engine adapter.
- [ ] 5.2 Add a QtWebEngine engine adapter without bundling QtWebEngine binaries.
- [ ] 5.3 Normalize load, navigation, resource, JavaScript, storage, event, error, snapshot, print, auto-height, permission, download, and capability behavior across both Linux adapters where native APIs allow.
- [ ] 5.4 Add dependency detection for WebKitGTK and QtWebEngine with actionable diagnostics.
- [ ] 5.5 Add tests for selected-engine capability reporting and missing-dependency diagnostics.

## 6. Documentation and Examples

- [ ] 6.1 Update quick start and loading docs with `loadHtmlCssString` examples for generated HTML, sanitized content, and virtual resources referenced from CSS.
- [ ] 6.2 Update Linux platform docs with KDE/QtWebEngine and GNOME/WebKitGTK defaults, explicit overrides, fallback policy, dependency installation notes, troubleshooting, and known differences.
- [ ] 6.3 Update `docs/platform_matrix.md` with QtWebEngine and WebKitGTK capability differences.
- [ ] 6.4 Add example app controls for HTML+CSS string loading and Linux engine selection/capability display.

## 7. Verification

- [ ] 7.1 Run formatting and static analysis across affected packages.
- [ ] 7.2 Run unit tests for composition, model validation, platform interface serialization, and Linux engine selection.
- [ ] 7.3 Run available Linux integration tests for WebKitGTK and QtWebEngine adapters, including explicit override and fallback cases.
- [ ] 7.4 Run conformance fixtures for HTML+CSS string rendering, blocked remote CSS resources, virtual CSS assets, and malformed markup.
- [ ] 7.5 Verify OpenSpec status and validation for this change before marking implementation complete.

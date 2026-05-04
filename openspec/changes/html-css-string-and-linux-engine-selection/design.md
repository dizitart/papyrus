## Context

The active `federated-native-webview` proposal defines Papyrus as a generic native system WebView package with `loadHtmlString` and Linux support through WebKitGTK. This change tightens two product requirements that need their own implementation contract: callers must be able to pass HTML and CSS as separate strings, and Linux must support both QtWebEngine and WebKitGTK with sensible desktop-environment defaults.

HTML+CSS string loading is needed for applications that keep sanitized body markup, generated CSS, and display policy separate until render time. KDE-based Linux distributions commonly expect Qt-native integration, while GNOME-based distributions commonly expect GTK/WebKit integration; Papyrus should expose that choice without making app code fork on desktop environment details.

## Goals / Non-Goals

**Goals:**

- Add a structured load API for HTML plus CSS strings without requiring callers to manually concatenate full documents.
- Preserve base URI, metadata, content security policy, virtual resource, navigation, and resource policy behavior for composed HTML+CSS loads.
- Compose CSS deterministically into a generated document or fragment wrapper while respecting caller order and media semantics.
- Add Linux engine selection modes: automatic, QtWebEngine, and WebKitGTK.
- Prefer QtWebEngine in KDE/Plasma environments and WebKitGTK in GNOME environments when automatic selection is enabled.
- Report selected engine, available engines, dependency problems, and engine-specific capability differences.
- Provide docs, examples, tests, and conformance fixtures for both features.

**Non-Goals:**

- Do not add a CSS parser, CSS sanitizer, or CSS compatibility shim.
- Do not guarantee identical rendering between QtWebEngine and WebKitGTK.
- Do not silently download, install, or bundle native Linux WebView dependencies.
- Do not remove WebKitGTK support for GNOME-based distributions.
- Do not make QtWebEngine the only Linux implementation.

## Decisions

### Add a Structured HTML+CSS Load Request

Papyrus will add a typed request such as `PapyrusHtmlCssRequest` and a convenience controller method such as `loadHtmlCssString(String html, String css, ...)`. The request will carry HTML, CSS, optional base URI, optional metadata, optional virtual resources, optional CSS media, and optional document composition settings.

Rationale: Separate fields keep call sites honest about what is markup versus style and allow Papyrus to apply the same security, base URI, virtual resource, and metadata flow as other load requests.

Alternative considered: tell callers to build a full HTML string themselves. That is simpler for Papyrus but pushes repeated, security-sensitive composition details into every app.

### Deterministic Document Composition

When given HTML+CSS strings, Papyrus will create a deterministic HTML document if the markup is a fragment, or inject a deterministic `<style>` element into the document head if the markup is already a full document. Caller CSS order must be preserved. CSS is not sanitized or parsed beyond safe document placement.

Rationale: WebView engines need a concrete document. Deterministic composition makes tests and CSP behavior predictable while avoiding a new rendering engine layer.

Alternative considered: load HTML first and inject CSS later through JavaScript. That risks visual flicker and violates strict JavaScript-disabled profiles.

### Keep Policy Enforcement Shared Across Load Types

HTML+CSS string loads will use the same navigation, resource, JavaScript, storage, CSP, virtual resource, event, and error contracts as HTML string loads. The platform interface will transport either the structured request or the generated document plus original metadata for diagnostics.

Rationale: This keeps the feature additive. Loading style separately should not create a side channel around security defaults.

Alternative considered: treat composed documents as a special platform-only path. That would duplicate policy behavior and make conformance harder.

### Add Linux Engine Selection to Configuration

Linux platform options will include an engine mode such as automatic, qtWebEngine, and webKitGtk. Automatic mode will inspect desktop environment signals such as `XDG_CURRENT_DESKTOP`, `DESKTOP_SESSION`, and related environment values, preferring QtWebEngine for KDE/Plasma and WebKitGTK for GNOME.

Rationale: The default should match the user’s desktop stack while still letting apps or distributions override the decision.

Alternative considered: choose at build time only. That is simple but makes one package less portable across Linux desktop environments.

### Prefer Explicit Failure Over Surprising Fallback

If the preferred automatic engine is unavailable, Papyrus may fall back only when fallback is enabled by policy; otherwise it must report a structured dependency or unavailable-engine error. Capability reporting must include selected engine and available engines.

Rationale: A silent engine swap can change rendering, storage, accessibility, and dependency behavior. Apps need to know what happened.

Alternative considered: always fall back to any available engine. That improves launch success but makes rendering and diagnostics unpredictable.

## Risks / Trade-offs

- QtWebEngine increases Linux dependency surface -> Document required packages, expose dependency diagnostics, and avoid bundling engine binaries.
- Automatic desktop detection can be wrong under custom sessions -> Provide explicit engine override and report selected engine.
- HTML+CSS composition can alter malformed input edge cases -> Define deterministic composition rules and add fixtures for full documents, fragments, malformed markup, and multiple CSS blocks.
- CSS string input may be mistaken for sanitization -> Document that Papyrus loads CSS as supplied and does not sanitize or validate it.
- Linux engines render differently -> Maintain engine-specific capability notes and avoid shared pixel-perfect baseline promises.
- Native implementation complexity grows -> Keep the public Linux package behind one platform interface with separate engine adapters internally.

## Migration Plan

1. Extend public API and platform interface models for `PapyrusHtmlCssRequest`, `loadHtmlCssString`, Linux engine mode, Linux engine diagnostics, and selected-engine capabilities.
2. Implement shared HTML+CSS composition and tests before platform work.
3. Route composed loads through existing platform load mechanisms.
4. Add WebKitGTK and QtWebEngine Linux engine adapters behind the Linux platform package.
5. Add automatic KDE/GNOME selection, explicit override behavior, dependency diagnostics, and fallback policy.
6. Update docs, examples, platform matrix, and conformance fixtures.

Existing `loadHtmlString` behavior remains valid. Apps that manually concatenate HTML and CSS can migrate to `loadHtmlCssString` when they want Papyrus-owned deterministic composition.

## Open Questions

- Should the CSS input support multiple named stylesheets at v1, or only one ordered list/string plus media metadata?
- Should fallback from QtWebEngine to WebKitGTK be disabled by default or enabled with a diagnostic event?
- Which Qt major version should the first Linux QtWebEngine implementation target?

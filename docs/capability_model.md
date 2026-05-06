# Capability Model

Papyrus is a generic controlled-HTML viewer built on native system WebViews.
It should expose the capabilities needed for privacy-sensitive document
rendering without hard-coding any email-specific pipeline behavior.

This document defines the required viewer surface in terms of generic WebView
functionality, grouped by capability area.

## Design Goals

- Keep the public API generic. Papyrus should expose capabilities, policies,
  and host hooks, not MIME parsing, sanitization, or mail-client behavior.
- Default to conservative behavior for untrusted HTML.
- Make privacy-sensitive knobs explicit rather than implicit.
- Prefer uniform cross-platform contracts, with runtime capability queries for
  backend-specific gaps.
- Separate caller-authored page behavior from host-authored control behavior.

## Capability Groups

### 1. Content Loading

Papyrus should support all of these load forms:

- HTML string loading with `baseUri`, metadata, and virtual resources.
- URL loading with optional request headers.
- Absolute local file loading.
- Byte-data loading with MIME type and optional encoding.
- Reload and stop-loading controls.

Current status:

- Already exposed: `PapyrusHtmlRequest`, `PapyrusUriRequest`,
  `PapyrusFileRequest`, `PapyrusDataRequest`, `reload`, `stopLoading`.
- Under-enforced: `loadData` parity is still incomplete in native backends.

### 2. Navigation Policy

Papyrus should let the host fully control navigation behavior:

- Allow or block navigation by default.
- Route external schemes to the host instead of the embedded WebView.
- Distinguish main-frame and sub-frame navigation.
- Require a user gesture before allowing external opens.
- Classify navigation type for links, forms, reloads, history, and scripted
  navigations.
- Support navigation callbacks before the navigation commits.

Current status:

- Already exposed in the model: `PapyrusNavigationPolicy`,
  `PapyrusNavigationRequest`, `onNavigationRequest`.
- Under-enforced: most native backends still serialize only a small subset of
  navigation policy and do not yet apply the full scheme/gesture/frame policy
  contract.

### 3. Resource and Network Policy

Papyrus should expose privacy-oriented resource controls:

- Disable all remote resources.
- Allow all remote resources.
- Allow remote resources only for an allowlist of hosts.
- Ask the host app about each request.
- Allowlist schemes.
- Block specific resource types such as images, fonts, scripts, media, or
  iframes.
- Serve app-owned virtual resources.
- Surface resource request metadata to the host.

Current status:

- Already exposed: `PapyrusResourcePolicy`, resource interception, virtual
  resources, provider registry, resource request/decision types.
- Under-enforced: resource policy is better covered than navigation policy, but
  enforcement still varies by backend and by request type.

### 4. Script and Bridge Policy

Papyrus should expose a script policy that clearly separates page-authored code
from host-authored control logic:

- JavaScript disabled, restricted, or unrestricted modes.
- Allowed JavaScript bridge channels.
- User-script injection controlled by policy.
- Explicit host-side JavaScript evaluation APIs.
- Clear documentation that CSP injection does not sanitize HTML.

Current status:

- Already exposed in the model: `PapyrusJavaScriptPolicy`,
  `evaluateJavaScript`, channel add/remove APIs, CSP injection helper.
- Under-enforced: most backends ignore `allowedChannels`, `allowUserScripts`,
  and injected scripts.
- Missing uniform backend parity: Linux and Windows do not yet expose a
  complete JavaScript-evaluation surface comparable to Android and Apple
  backends.

### 5. Storage and Privacy Isolation

Papyrus should let the host choose how much WebView state is retained:

- Cookie policy.
- Local-storage policy.
- Cache policy.
- Ephemeral versus persistent sessions.
- Optional storage partition identifiers.
- Explicit cache and storage clearing APIs.

Current status:

- Already exposed in the model: `PapyrusStoragePolicy`, `clearCache`,
  `clearStorage`.
- Under-enforced: cookie/local-storage/cache/partition settings are not wired
  uniformly across native backends.

### 6. Security and Permission Policy

Papyrus should surface all WebView security toggles that materially affect
privacy or privilege:

- File access.
- Universal access from file URLs.
- Mixed-content loading.
- Popup creation.
- Clipboard read and write.
- Geolocation.
- Camera and microphone.
- Protected media.
- Inline media playback.
- Content isolation.
- Caller-supplied CSP injection for HTML loads.

Current status:

- Already declared in `PapyrusSecurityPolicy`.
- Under-enforced: only a subset is serialized into backend config maps and an
  even smaller subset is applied by native engines.

### 7. Media, Rendering, and Appearance

Papyrus should expose rendering and playback controls relevant to controlled
document viewers:

- Autoplay policy.
- Inline playback policy.
- User-gesture requirement for playback.
- Fullscreen enablement.
- Auto-height measurement.
- Min/max height bounds.
- Zoom enablement.
- Text zoom.
- Background color.
- Dark-mode preference.
- Viewport policy.

Current status:

- Mostly declared in `PapyrusMediaPolicy` and `PapyrusDisplayPolicy`.
- Under-enforced: many of these fields are not serialized or applied in native
  backends yet.

### 8. User Interaction Surface

Papyrus should expose generic interaction controls needed by document-viewer
hosts while remaining content-agnostic:

- Enable or disable text selection.
- Enable or disable the default context menu.
- Retrieve the current selected text.
- Copy the current selection.
- Produce a quoted representation of the current selection.
- Optionally suppress long-press interaction when selection and context menus
  are disabled.

Current status:

- Already exposed: `PapyrusInteractionPolicy`, `selectedText`,
  `copySelection`, `quoteSelection`, and shared config serialization for
  selection, long-press, and default context-menu policy.
- Partially enforced: Android and Windows now honor context-menu suppression
  through shared policy hooks, but custom context-menu replacement and stricter
  selection-policy enforcement are not implemented uniformly yet.
- Live-tested today: selection/query/copy/quote flows are covered on macOS,
  iOS, and Android.

### 9. Output and Export

Papyrus should expose output paths that a document-viewer host may need:

- Snapshot capture.
- Printing.
- Download interception.
- Host-owned download handoff.

Current status:

- Already exposed: snapshot, print, download request surface, capabilities.
- Under-enforced: print and snapshot behavior still vary by backend and test
  environment.

### 10. Observability and Host Hooks

Papyrus should expose enough runtime visibility for hosts to make policy
decisions:

- Page started, progress, and page finished.
- URL and title queries.
- Structured errors.
- Console messages.
- Web messages.
- Permission requests.
- Download requests.
- Resource requests.
- Content size changes.
- Platform capability queries.

Current status:

- Mostly already exposed through `PapyrusView` callbacks, event types, and the
  controller.
- Under-enforced: some callback types exist in the spec/model but are not yet
  surfaced consistently from all native backends.

### 11. Accessibility and Embedder Control

Papyrus should continue to expose host-facing embedder knobs:

- Native accessibility semantics.
- Debugging enablement.
- Hardware acceleration preference.
- Desktop overlay versus native platform view where relevant.

Current status:

- Already exposed in `PapyrusAccessibilityPolicy` and
  `PapyrusPlatformOptions`.
- Under-enforced: accessibility and hardware-acceleration choices are not yet
  consistently applied across native backends.

## Required Public Surface Summary

The generic Papyrus capability surface should cover these categories:

- Load requests.
- Navigation policy.
- Resource policy.
- Script/bridge policy.
- Storage/privacy policy.
- Security/permission policy.
- Media/display policy.
- User interaction policy.
- Output/export APIs.
- Observability/events.
- Runtime capability queries.

## Immediate Gaps To Close

The current repository has three concrete gaps:

1. Interaction policy enforcement is still partial.
  Papyrus now exposes a generic interaction contract, but backend enforcement
  for text selection, long-press suppression, and context-menu replacement is
  not uniform yet.

2. Many existing policy fields are model-only.
   `PapyrusSecurityPolicy`, `PapyrusNavigationPolicy`, `PapyrusStoragePolicy`,
   `PapyrusMediaPolicy`, and parts of `PapyrusDisplayPolicy` define knobs that
   are not yet serialized or enforced uniformly by native backends.

3. Conformance coverage is incomplete.
   The repository has strong baseline conformance work for loading,
   interception, snapshotting, printing, and storage, but it does not yet have
   comprehensive platform tests for the broader policy and interaction surface.

## Implementation Order

To keep the work tractable and cross-platform:

1. Finish enforcing the shared interaction policy across all native backends.
2. Serialize the broader existing policy surface into platform config maps.
3. Apply the remaining security, navigation, storage, and display knobs in the
  native engines.
4. Add contract tests for the full public API.
5. Add live backend conformance scenarios for the features that can be tested
  non-interactively on every platform.

This keeps Papyrus generic while making it practical for privacy-sensitive HTML
viewer use cases such as receipts, statements, sanitized newsletters, help
documents, or HTML email rendering performed by a separate host pipeline.
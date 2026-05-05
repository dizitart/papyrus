# webview-events-and-capabilities Specification

## Purpose
TBD - created by archiving change federated-native-webview. Update Purpose after archive.
## Requirements
### Requirement: Lifecycle and Event Model
Papyrus SHALL expose deterministic callback-style and stream-style events for page start, page finish, progress, title changes, URL changes, console messages, web messages, navigation requests, resource requests, download requests, permission requests, errors, and content-size changes.

#### Scenario: Page load emits lifecycle
- **WHEN** a page begins loading and then finishes loading
- **THEN** Papyrus emits page-started, progress, and page-finished events with the associated URI where available

### Requirement: Structured Error Codes
Papyrus SHALL map failures to structured error codes including unknown, navigation blocked, resource blocked, network failed, SSL failed, timeout, renderer crashed, unsupported platform feature, invalid load request, and WebView unavailable.

#### Scenario: WebView runtime unavailable
- **WHEN** the native WebView runtime cannot be created
- **THEN** Papyrus reports `webViewUnavailable` with a host-readable error message

### Requirement: Content Size Reporting
Papyrus SHALL support content size query and content-size change reporting where supported, including auto-height policy integration.

#### Scenario: Auto-height content changes
- **WHEN** loaded content changes its document height and auto-height measurement is enabled
- **THEN** Papyrus emits a `PapyrusContentSizeChangedEvent` or reports that auto-height is unsupported on the platform

### Requirement: Snapshot and Print
Papyrus SHALL support snapshot capture and document printing where supported, and SHALL report structured unsupported-feature errors where unavailable.

#### Scenario: Snapshot unsupported
- **WHEN** the host calls `captureSnapshot` on a platform that cannot support it
- **THEN** Papyrus completes with an `unsupportedPlatformFeature` error instead of silently succeeding with invalid data

### Requirement: Platform Capability Query
Papyrus SHALL expose platform capability information for resource interception, virtual schemes, ephemeral storage, print, snapshot, auto-height, dark mode, download interception, and permission interception.

#### Scenario: Host queries platform capabilities
- **WHEN** the host calls `getPapyrusCapabilities`
- **THEN** Papyrus returns booleans describing the currently registered platform implementation

### Requirement: Internal Measurement Isolation
Papyrus SHALL keep internal measurement scripts or bridges separate from caller-controlled JavaScript and SHALL NOT enable arbitrary page JavaScript solely because content-size measurement is enabled.

#### Scenario: Measurement with JavaScript disabled
- **WHEN** auto-height measurement is enabled and `PapyrusJavaScriptMode.disabled` is active
- **THEN** Papyrus performs measurement through native or isolated mechanisms where possible without enabling page-authored JavaScript


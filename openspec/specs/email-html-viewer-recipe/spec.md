# email-html-viewer-recipe Specification

## Purpose
TBD - created by archiving change federated-native-webview. Update Purpose after archive.
## Requirements
### Requirement: Email Support Through Generic APIs
Papyrus SHALL support sanitized email HTML viewing through generic HTML loading, virtual resources, resource policy, navigation policy, display policy, print, snapshot, and event APIs without making email the package identity.

#### Scenario: Sanitized email HTML is loaded
- **WHEN** a mail application passes sanitized HTML, a base URI, metadata, and inline resources to `PapyrusHtmlRequest`
- **THEN** Papyrus renders the prepared content using generic WebView APIs

### Requirement: Email Viewer Profile
Papyrus SHALL provide `PapyrusProfiles.emailHtmlViewer()` as a convenience profile that disables JavaScript, blocks remote resources by default, disables storage, opens navigation externally only under host policy, and supports auto-height-oriented display configuration.

#### Scenario: Email profile blocks remote resources
- **WHEN** email HTML references a remote tracking image under the email viewer profile
- **THEN** Papyrus blocks the remote request by default

### Requirement: MIME Pipeline Separation
Papyrus SHALL NOT parse MIME, select message body parts, decode charsets, extract CIDs, extract attachments, sanitize HTML, clean CSS, rewrite links, define tracking policy, or sync mailboxes.

#### Scenario: Host provides unsanitized MIME message
- **WHEN** a host attempts to treat Papyrus as a MIME parser or sanitizer
- **THEN** Papyrus provides no API that accepts raw MIME as the rendering input

### Requirement: Email Resource Mapping
Papyrus SHALL allow mail applications to map inline attachments, CID-style resources, locally cached images, generated CSS, and app-packaged assets through `PapyrusVirtualResource` and `PapyrusVirtualResourceProvider`.

#### Scenario: CID-style inline image is prepared by host
- **WHEN** the mail pipeline converts a CID image into a Papyrus virtual resource URI
- **THEN** Papyrus can serve that resource through the virtual resource system without exposing arbitrary file access

### Requirement: Honest Email Rendering Correctness
Papyrus SHALL document that email rendering correctness depends on sanitized prepared HTML, conservative policies, native browser-engine rendering, and representative snapshot tests, and SHALL NOT promise pixel-perfect parity with specific email clients.

#### Scenario: Cross-engine rendering differs
- **WHEN** the same prepared email renders differently on WKWebView and WebView2
- **THEN** Papyrus treats this as a native engine difference unless a Papyrus API or policy contract was violated


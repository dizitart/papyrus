## ADDED Requirements

### Requirement: Virtual Resource Model
Papyrus SHALL support app-owned virtual resources with URI, bytes, MIME type, and response headers so callers can serve controlled local content into the WebView without enabling arbitrary file access.

#### Scenario: HTML references a virtual image
- **WHEN** loaded HTML references a URI backed by a `PapyrusVirtualResource`
- **THEN** Papyrus serves the configured bytes with the configured MIME type and headers

### Requirement: Resource Request Interception
Papyrus SHALL surface resource requests with URI, method, headers, resource type, and frame information when platform interception is supported and request interception is enabled.

#### Scenario: Host blocks tracking image
- **WHEN** loaded content requests a remote image and the host returns `PapyrusBlockResource`
- **THEN** Papyrus prevents that resource from loading

### Requirement: Resource Policy Modes
Papyrus SHALL support remote resource modes for block, allow all, allow by host, and ask host app, along with allowed hosts, allowed schemes, blocked resource types, virtual resource origin, and interception enablement.

#### Scenario: Remote resources are blocked
- **WHEN** remote resource mode is `block` and loaded content requests an HTTPS image
- **THEN** Papyrus blocks the request unless it is resolved as an allowed virtual or app-provided resource

### Requirement: Resource Provider Registry
Papyrus SHALL allow host apps to register and unregister one or more virtual resource providers.

#### Scenario: Provider resolves CSS
- **WHEN** an intercepted stylesheet request matches a registered provider
- **THEN** Papyrus can respond with `PapyrusRespondWithResource` using the provider response


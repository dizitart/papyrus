## ADDED Requirements

### Requirement: HTML and CSS String Load Request
Papyrus SHALL expose a typed load request and controller convenience method for loading HTML and CSS supplied as separate strings.

#### Scenario: Host loads separate HTML and CSS strings
- **WHEN** the host calls the HTML+CSS string load API with markup and stylesheet text
- **THEN** Papyrus loads a composed document that applies the supplied CSS to the supplied HTML

### Requirement: Deterministic Composition
Papyrus SHALL compose HTML+CSS string loads deterministically by preserving CSS order, placing CSS in document style elements, and using stable document wrapping rules for fragments and full HTML documents.

#### Scenario: Fragment HTML is loaded with CSS
- **WHEN** the host loads an HTML fragment and CSS string
- **THEN** Papyrus wraps the fragment in a stable document structure and places the CSS before body content is rendered

#### Scenario: Full HTML document is loaded with CSS
- **WHEN** the host loads a full HTML document and CSS string
- **THEN** Papyrus injects the CSS into the document head using deterministic placement

### Requirement: Base URI and Virtual Resource Support
HTML+CSS string loads SHALL support base URI, metadata, and virtual resources with the same semantics as HTML string loads.

#### Scenario: CSS references a virtual font
- **WHEN** CSS supplied to the HTML+CSS string load references a virtual resource URI
- **THEN** Papyrus resolves that resource through the configured virtual resource system

### Requirement: Policy Consistency
HTML+CSS string loads SHALL honor the same security, JavaScript, navigation, resource, storage, content security policy, event, and error behavior as HTML string loads.

#### Scenario: CSS load under locked-down profile
- **WHEN** the host loads HTML+CSS strings under a locked-down profile
- **THEN** JavaScript remains disabled, remote resources follow resource policy, and navigation remains intercepted

### Requirement: No CSS Sanitization Claim
Papyrus SHALL document that HTML+CSS string loading does not sanitize, validate, rewrite, or make unsafe CSS safe.

#### Scenario: Caller supplies unsafe CSS
- **WHEN** the host supplies CSS with unsafe or unwanted external references
- **THEN** Papyrus applies configured resource policies but does not claim that the CSS itself was sanitized

### Requirement: HTML+CSS Load Tests
Papyrus SHALL include tests for fragment composition, full-document composition, CSS ordering, base URI behavior, CSP behavior, virtual resources, blocked remote CSS resources, malformed browser-recoverable markup, and event/error reporting.

#### Scenario: Composition tests run
- **WHEN** the HTML+CSS string loading tests run
- **THEN** they verify deterministic output and policy behavior for both fragment and full-document inputs


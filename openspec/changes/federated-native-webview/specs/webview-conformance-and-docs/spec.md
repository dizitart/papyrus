## ADDED Requirements

### Requirement: Unit Test Coverage
Papyrus SHALL include unit tests for configuration defaults, policy serialization, load request validation, navigation decisions, resource decisions, virtual resource lookup, error mapping, and capability mapping.

#### Scenario: Defaults are tested
- **WHEN** unit tests run
- **THEN** they verify that default policies are conservative and match the public API contract

### Requirement: Platform Integration Tests
Papyrus SHALL include platform integration tests for loading HTML, loading remote URLs, local file access when enabled, local file blocking when disabled, JavaScript blocking/enabling, link interception, resource interception, virtual resources, auto-height, snapshot, print or unsupported print, and WebView unavailable handling where testable.

#### Scenario: JavaScript disabled integration test
- **WHEN** integration tests load content containing JavaScript under the default configuration
- **THEN** the test verifies that page-authored JavaScript does not execute

### Requirement: Controlled Content Scenario Fixtures
Papyrus SHALL include generic scenario fixtures for table-heavy HTML, nested tables, inline CSS, blocked external CSS, virtual images, blocked tracking pixels, large newsletters, receipts, RTL content, CJK content, emoji/web-safe fonts, dark-mode-sensitive HTML, long URLs, and malformed browser-recoverable HTML.

#### Scenario: Tracking pixel fixture
- **WHEN** the conformance suite loads a fixture with a remote tracking pixel under a strict profile
- **THEN** the suite verifies that the remote resource is blocked

### Requirement: Per-Platform Screenshot Baselines
Papyrus SHALL provide screenshot/golden test support with per-platform baselines and SHALL NOT compare all native engines against a single universal baseline.

#### Scenario: Screenshot baselines are generated
- **WHEN** screenshots are captured on Android, iOS, macOS, Windows, or Linux
- **THEN** they are compared only against the matching platform baseline

### Requirement: Documentation Set
Papyrus SHALL document quick start, loading HTML, loading URLs, loading files, security profiles, navigation interception, resource interception, virtual resources, JavaScript policy, storage/cookie policy, auto-height, printing, snapshotting, platform capability matrix, email HTML viewer recipe, known platform differences, and migration from existing WebView packages.

#### Scenario: Developer reads docs
- **WHEN** a developer needs to use Papyrus for controlled HTML
- **THEN** the documentation explains the relevant load, policy, resource, capability, and platform behavior without requiring source-code inspection

### Requirement: Example Application
Papyrus SHALL include a full example app demonstrating generic document viewing, trusted app content, URL loading, strict policies, virtual resources, platform capabilities, snapshot/print where supported, and sanitized email HTML viewing.

#### Scenario: Example app runs
- **WHEN** the example app is launched on a supported platform
- **THEN** it demonstrates the core WebView features and reports unsupported platform capabilities visibly


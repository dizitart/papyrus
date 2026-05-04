## ADDED Requirements

### Requirement: Linux Engine Modes
Papyrus SHALL support Linux WebView engine modes for automatic selection, QtWebEngine, and WebKitGTK.

#### Scenario: Host forces QtWebEngine
- **WHEN** the Linux platform configuration selects QtWebEngine explicitly
- **THEN** Papyrus attempts to create the Linux WebView using QtWebEngine and reports a structured error if QtWebEngine is unavailable

#### Scenario: Host forces WebKitGTK
- **WHEN** the Linux platform configuration selects WebKitGTK explicitly
- **THEN** Papyrus attempts to create the Linux WebView using WebKitGTK and reports a structured error if WebKitGTK is unavailable

### Requirement: Desktop Environment Automatic Selection
In automatic Linux engine mode, Papyrus SHALL prefer QtWebEngine for KDE/Plasma desktop environments and WebKitGTK for GNOME desktop environments.

#### Scenario: KDE automatic selection
- **WHEN** Papyrus runs on Linux with desktop environment signals indicating KDE or Plasma and automatic engine selection is enabled
- **THEN** Papyrus selects QtWebEngine as the preferred Linux WebView engine

#### Scenario: GNOME automatic selection
- **WHEN** Papyrus runs on Linux with desktop environment signals indicating GNOME and automatic engine selection is enabled
- **THEN** Papyrus selects WebKitGTK as the preferred Linux WebView engine

### Requirement: Engine Availability Diagnostics
Papyrus SHALL detect and report Linux engine availability, missing native dependencies, selected engine, attempted engine, and fallback decisions through structured diagnostics and capability reporting.

#### Scenario: Preferred Linux engine is missing
- **WHEN** the preferred Linux engine cannot be created because required native dependencies are missing
- **THEN** Papyrus reports the missing dependency condition and the attempted engine in a structured error or diagnostic event

### Requirement: Explicit Fallback Policy
Papyrus SHALL make fallback from the preferred Linux engine to another installed Linux engine explicit and configurable.

#### Scenario: Fallback disabled
- **WHEN** automatic mode prefers QtWebEngine, QtWebEngine is unavailable, WebKitGTK is available, and fallback is disabled
- **THEN** Papyrus does not silently create WebKitGTK and instead reports the QtWebEngine availability failure

#### Scenario: Fallback enabled
- **WHEN** automatic mode prefers QtWebEngine, QtWebEngine is unavailable, WebKitGTK is available, and fallback is enabled
- **THEN** Papyrus creates WebKitGTK and reports that fallback occurred

### Requirement: Linux Engine Capability Differences
Papyrus SHALL expose capability differences for QtWebEngine and WebKitGTK, including resource interception, virtual resource support, ephemeral storage, snapshot, print, auto-height, dark mode, download interception, and permission interception.

#### Scenario: Host queries selected Linux engine capabilities
- **WHEN** the host queries Papyrus capabilities on Linux
- **THEN** the returned capabilities include the selected engine and engine-specific support flags

### Requirement: Linux Engine Documentation and Tests
Papyrus SHALL document KDE/QtWebEngine and GNOME/WebKitGTK behavior, required system packages, override configuration, fallback policy, known differences, and troubleshooting, and SHALL include tests for selection and diagnostics.

#### Scenario: Linux platform matrix is reviewed
- **WHEN** a developer reads the Linux platform documentation
- **THEN** it explains how automatic selection works, how to override the engine, which dependencies are required, and how unsupported or missing engines are reported


## ADDED Requirements

### Requirement: Papyrus View Widget
Papyrus SHALL expose `PapyrusView` as the top-level Flutter widget for embedding a native WebView with a required controller, optional initial load request, configuration, gesture recognizers, lifecycle callbacks, navigation/resource/download/permission handlers, console/web-message handlers, error handlers, and content-size handlers.

#### Scenario: Host creates a configured view
- **WHEN** a host app creates `PapyrusView` with a controller, configuration, and initial HTML request
- **THEN** Papyrus creates the native WebView, applies the configuration, loads the request, and emits the configured lifecycle callbacks

### Requirement: Controller Operations
Papyrus SHALL expose a `PapyrusController` that supports loading HTML strings, URIs, files, and byte data; reload and stop; back/forward navigation; state query; JavaScript evaluation and channels where allowed; content-size query; snapshot; print; cache/storage clearing; and disposal.

#### Scenario: Host performs controller lifecycle
- **WHEN** the host loads content, queries progress and title, captures a snapshot, clears storage, and disposes the controller
- **THEN** each operation completes through the shared controller contract or returns a structured unsupported/error result

### Requirement: Load Request Models
Papyrus SHALL define typed load request models for HTML, URI, file, and byte-data loads, including base URI, headers, metadata, MIME type, encoding, and virtual resources where applicable.

#### Scenario: HTML request includes virtual resources
- **WHEN** the host loads `PapyrusHtmlRequest` with HTML, a base URI, metadata, and virtual resources
- **THEN** Papyrus loads the HTML and makes the virtual resources available through the configured resource mechanism

### Requirement: Configuration and Profiles
Papyrus SHALL expose `PapyrusConfiguration` with security, navigation, resources, JavaScript, storage, media, display, accessibility, and platform policy objects, plus built-in `lockedDown`, `documentViewer`, `trustedAppContent`, `browserLike`, and `emailHtmlViewer` profiles.

#### Scenario: Host selects a built-in profile
- **WHEN** the host selects `PapyrusProfiles.lockedDown()`
- **THEN** the resulting configuration uses conservative settings suitable for untrusted static HTML

### Requirement: Public Extension Points
Papyrus SHALL expose resource providers, resource registries, navigation resolvers, resource resolvers, and platform capability queries so host apps can extend behavior without forking platform packages.

#### Scenario: Host registers a resource provider
- **WHEN** the host registers a `PapyrusVirtualResourceProvider`
- **THEN** Papyrus can ask the provider to resolve intercepted resource requests and respond with app-owned bytes


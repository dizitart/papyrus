## ADDED Requirements

### Requirement: Conservative Default Security
Papyrus SHALL default to JavaScript disabled, popups disabled, file access disabled, universal file URL access disabled, mixed content blocked where supported, protected media disabled, device permissions disabled, content isolation enabled, intercepted navigation, and host-surfaced downloads.

#### Scenario: Default configuration loads untrusted HTML
- **WHEN** a host loads an HTML string with the default configuration
- **THEN** scripts, popups, arbitrary file access, universal file URL access, silent device permissions, and automatic downloads are not allowed

### Requirement: Navigation Policy Enforcement
Papyrus SHALL enforce navigation policies for default decisions, allowed schemes, external schemes, blocked schemes, user-gesture requirements, main-frame navigation, and sub-frame navigation.

#### Scenario: Blocked scheme navigation
- **WHEN** loaded content attempts to navigate to a blocked `javascript:` URI
- **THEN** Papyrus blocks the navigation and reports the blocked decision through the navigation contract

### Requirement: JavaScript Policy Enforcement
Papyrus SHALL disable page-authored JavaScript by default and SHALL only enable restricted or unrestricted JavaScript behavior when the configuration explicitly allows it.

#### Scenario: Script attempts to run while disabled
- **WHEN** loaded content contains a script and `PapyrusJavaScriptMode.disabled` is active
- **THEN** page-authored script execution is prevented

### Requirement: Storage and Isolation Policy
Papyrus SHALL enforce cookie, local storage, cache, ephemeral storage, and partition settings according to `PapyrusStoragePolicy`.

#### Scenario: Locked-down storage is ephemeral
- **WHEN** locked-down or email-style content is loaded
- **THEN** cookies and local storage are disabled and persistent state is not silently shared with other WebView sessions

### Requirement: Media, Permission, and Download Policy
Papyrus SHALL enforce media autoplay, inline playback, fullscreen, permission request, and download decision policies without silently granting sensitive capabilities.

#### Scenario: Camera permission is requested
- **WHEN** loaded content requests camera access
- **THEN** Papyrus denies or surfaces the request to the host according to policy and never grants it silently

### Requirement: Content Security Policy Injection
For HTML string loads, Papyrus SHALL support deterministic caller-supplied Content Security Policy injection when equivalent native enforcement is unavailable, and SHALL document that this does not sanitize unsafe HTML.

#### Scenario: Caller supplies CSP for HTML load
- **WHEN** an HTML string load includes a configured content security policy
- **THEN** Papyrus applies the policy deterministically or reports the platform limitation without claiming to sanitize the document


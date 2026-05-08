# papyrus

A policy-driven federated native WebView for Flutter. Papyrus embeds the platform system WebView on each supported target and exposes a uniform, conservative-by-default API for loading, navigation, resource control, security, storage, and interaction policy.

Papyrus is designed for controlled HTML rendering — document viewers, email HTML renderers, sandboxed content panels — not as a general-purpose browser shell.

## Features

- `PapyrusView` widget with a `PapyrusController` for programmatic control
- Policy-first design: security, navigation, storage, and interaction policies
- Runtime capability detection via `PapyrusController.getCapabilities()`
- Resource interception with custom response injection
- Ephemeral / partitioned storage profiles
- Print, snapshot, auto-height, `clearCache`, `clearStorage`
- Structured error reporting (`PapyrusError`, `PapyrusNavigationBlockedError`, `PapyrusWebViewUnavailableError`)

## Platform support

| Platform | Engine | Embedded view | Resource interception | Ephemeral storage |
|---|---|:---:|:---:|:---:|
| Android | Android System WebView | ✓ | ✓ | ✓ |
| iOS | WKWebView | ✓ | ✓ | ✓ |
| macOS | WKWebView | ✓ (overlay) | ✓ | ✓ |
| Windows | WebView2 | ✓ (overlay) | ✓ | Partial |
| Linux | WebKitGTK | ✓ (overlay) | Feasible | ✓ |

## Getting started

```yaml
dependencies:
  papyrus: ^0.1.0
```

## Usage

```dart
import 'package:papyrus/papyrus.dart';

PapyrusView(
  controller: PapyrusController(
    initialRequest: PapyrusLoadRequest.url('https://example.com'),
    securityPolicy: PapyrusSecurityPolicy(
      allowInsecureContent: false,
      allowFileAccess: false,
    ),
  ),
)
```

## Platform-specific setup

### macOS
Add `com.apple.security.network.client` to both `DebugProfile.entitlements`
and `Release.entitlements` in your macOS runner.

### Windows
Microsoft Edge WebView2 Runtime must be installed on the end-user machine.
See the [`papyrus_windows` README](https://github.com/dizitart/papyrus/tree/main/packages/papyrus_windows)
for packaging options.

### Linux
Install WebKitGTK development packages (`libwebkit2gtk-4.1-0` on Ubuntu 22.04+).
See the [`papyrus_linux` README](https://github.com/dizitart/papyrus/tree/main/packages/papyrus_linux)
for distribution-specific details.

## Additional information

- [Repository](https://github.com/dizitart/papyrus)
- [Issue tracker](https://github.com/dizitart/papyrus/issues)
- [Architecture docs](https://github.com/dizitart/papyrus/tree/main/docs)

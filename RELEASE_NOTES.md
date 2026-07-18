# Release Notes

## 0.2.0

- Added `PapyrusConfiguration.userAgent` to override the session User-Agent
  string. When set, it is applied globally by every native backend (Android,
  iOS, macOS, Windows, Linux) — affecting sub-resources, XHR/fetch, and
  `navigator.userAgent`, not only the top-level document request.

## 0.1.1

- Added package-local LICENSE files and runnable package examples.
- Expanded public API documentation for the Papyrus controller and widget APIs.
- Refined documentation and package metadata for improved pub.dev score
  conformance.
- Published federated packages at 0.1.1: `papyrus`, `papyrus_platform_interface`,
  `papyrus_android`, `papyrus_ios`, `papyrus_macos`, `papyrus_windows`, and
  `papyrus_linux`.

## 0.1.0

- Initial federated package structure.
- Public Papyrus widget/controller API.
- Shared platform interface, policy models, events, errors, resources, and
  capability contracts.
- Initial documentation, example app, and conformance fixture structure.


# Platform Matrix

| Platform | Engine | Embedded view | Resource interception | Ephemeral storage | Print | Snapshot | Auto-height |
|---|---|---:|---:|---:|---:|---:|---:|
| Android | Android System WebView | Yes | Yes | Yes | Yes | Yes | Yes |
| iOS | WKWebView | Yes | Yes | Yes | Yes | Yes | Yes |
| macOS | WKWebView | Yes, desktop overlay by default | Yes | Yes | Yes | Yes | Yes |
| Windows | WebView2 | Yes, desktop overlay | Yes | Partial | Yes | Partial | Yes |
| Linux | WebKitGTK | Yes, desktop overlay | Feasible | Yes | Partial | Partial | Yes |

Capability queries are authoritative at runtime. This matrix documents expected
v1 behavior, not a substitute for `PapyrusController.getCapabilities()`.

Windows and Linux do not use Flutter platform views. `PapyrusView` lays out a
Flutter-owned placeholder and the platform package positions a native WebView
overlay over that rectangle. This keeps the public widget behavior uniform while
using the native desktop primitives available to those embedders.

macOS prefers the same desktop overlay strategy by default. Set
`PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW=true` only when explicitly testing the
AppKit platform-view path.

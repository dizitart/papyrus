# Platform Matrix

| Platform | Engine | Embedded view | Resource interception | Ephemeral storage | Print | Snapshot | Auto-height |
|---|---|---:|---:|---:|---:|---:|---:|
| Android | Android System WebView | Yes | Yes | Yes | Yes | Yes | Yes |
| iOS | WKWebView | Yes | Yes | Yes | Yes | Yes | Yes |
| macOS | WKWebView | Yes | Yes | Yes | Yes | Yes | Yes |
| Windows | WebView2 | No | Yes | Partial | Yes | Yes | Yes |
| Linux | WebKitGTK | No | Feasible | Yes | Partial | Yes | Yes |

Capability queries are authoritative at runtime. This matrix documents expected
v1 behavior, not a substitute for `PapyrusController.getCapabilities()`.

Windows and Linux currently expose method-channel capability stubs but do not
have an embeddable Flutter platform-view surface in this package. `PapyrusView`
shows an explicit unsupported surface on those platforms instead of rendering a
blank zero-size widget.

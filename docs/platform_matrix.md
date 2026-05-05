# Platform Matrix

| Platform | Engine | Resource interception | Ephemeral storage | Print | Snapshot | Auto-height |
|---|---|---:|---:|---:|---:|---:|
| Android | Android System WebView | Yes | Yes | Yes | Yes | Yes |
| iOS | WKWebView | Yes | Yes | Yes | Yes | Yes |
| macOS | WKWebView | Yes | Yes | Yes | Yes | Yes |
| Windows | WebView2 | Yes | Partial | Yes | Yes | Yes |
| Linux | WebKitGTK | Feasible | Yes | Partial | Yes | Yes |

Capability queries are authoritative at runtime. This matrix documents expected
v1 behavior, not a substitute for `getPapyrusCapabilities()`.


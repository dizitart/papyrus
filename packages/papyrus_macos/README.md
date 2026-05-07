# papyrus_macos

macOS WKWebView implementation package for Papyrus.

The native implementation aligns with iOS WKWebView behavior and adds macOS
handling for print, keyboard, accessibility, context menus, and scroll behavior.

Sandboxed macOS runners must include `com.apple.security.network.client` in
both `DebugProfile.entitlements` and `Release.entitlements` so `WKWebView` can
load content reliably.

Papyrus uses the desktop overlay path by default on macOS. Set
`PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW=true` only when explicitly testing the
AppKit platform-view path.

## macOS distribution

WKWebView is a system framework bundled with macOS — no WebKit redistributable
is required in the app bundle. The minimum macOS version for the WKWebView
features used by Papyrus is **10.15 Catalina**.

| Distribution type | Required entitlement | Notes |
|---|---|---|
| Direct distribution (DMG / PKG) | `com.apple.security.network.client` | Add to both Debug/Profile and Release entitlement files |
| Mac App Store | `com.apple.security.network.client` | Required for sandbox; add via Xcode capabilities |
| Notarized app | `com.apple.security.network.client` | Hardened runtime must also be enabled |

No additional runtime installer is needed. WKWebView receives security updates
as part of macOS system updates — the host app inherits those automatically.


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


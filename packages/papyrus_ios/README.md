# papyrus_ios

iOS WKWebView implementation package for Papyrus.

The native implementation maps Papyrus policies to `WKWebViewConfiguration`,
`WKNavigationDelegate`, non-persistent storage, scheme handling, file-access
constraints, and content-size observation.

Inline HTML without a base URI is loaded through a `data:` URL so the Apple
WKWebView path stays aligned with the macOS implementation.

iOS does not use the macOS sandbox entitlement model, so there is no
`com.apple.security.network.client` runner entitlement to add here. If the host
app loads insecure remote content, configure App Transport Security in the iOS
runner as needed.


# papyrus_windows

Windows WebView2 implementation package for Papyrus.

The native implementation detects missing WebView2 Runtime, maps policy to
CoreWebView2 settings, intercepts navigation/resources, handles process failure
events, and reports capability differences.

Windows uses the shared desktop overlay model rather than a Flutter platform
view. `PapyrusView` lays out a Flutter placeholder and the plugin positions the
native WebView2 surface over that rectangle via `setViewport`.


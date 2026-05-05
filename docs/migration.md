# Migration

From `webview_flutter` or similar packages:

1. Create a `PapyrusController` with `PapyrusController.create()`.
2. Replace direct WebView widget construction with `PapyrusView`.
3. Choose an explicit `PapyrusProfiles` preset.
4. Move navigation, resource, permission, and download decisions into Papyrus
   policy callbacks.
5. Query `PapyrusPlatformCapabilities` before using optional features such as
   print, snapshot, and auto-height.

Papyrus is not a browser shell and does not include tabs, bookmarks, address bar
UI, MIME parsing, or sanitization.


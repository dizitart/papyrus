# papyrus_windows

Windows WebView2 implementation package for Papyrus.

The native implementation detects missing WebView2 Runtime, maps policy to
CoreWebView2 settings, intercepts navigation/resources, handles process failure
events, and reports capability differences.

If WebView2 runtime creation fails, Papyrus reports
`webViewUnavailable` with actionable diagnostics.

Windows uses the shared desktop overlay model rather than a Flutter platform
view. `PapyrusView` lays out a Flutter placeholder and the plugin positions the
native WebView2 surface over that rectangle via `setViewport`.
Initial loads are scheduled after viewport synchronization so first paint does
not race zero-sized bounds during startup.

## Native Windows tests

From `examples/papyrus_example`:

```pwsh
flutter pub get
flutter build windows --debug
cmake -S windows -B build/windows/x64 "-Dinclude_papyrus_windows_tests=ON" "-DCMAKE_POLICY_VERSION_MINIMUM=3.10"
cmake --build build/windows/x64 --config Debug --target papyrus_windows_test
ctest --test-dir build/windows/x64/plugins/papyrus_windows -C Debug --output-on-failure
```

## Packaging Windows installers (WebView2 dependencies)

Papyrus links the WebView2 loader statically, so apps do not need to ship
`WebView2Loader.dll`. The required runtime dependency is Microsoft Edge
WebView2 Runtime.

Recommended installer strategies:

1. Evergreen Bootstrapper (small online installer)
	 - Bundle or download `MicrosoftEdgeWebView2Setup.exe`.
	 - Run silently during install: `/silent /install`.
	 - Best when internet access is available.

2. Evergreen Standalone Installer (offline)
	 - Bundle architecture-specific runtime installers (x64/x86/arm64).
	 - Run silently during install: `/silent /install`.
	 - Best for offline or controlled enterprise environments.

Current Papyrus behavior:

- The Windows plugin creates WebView2 with
	`CreateCoreWebView2EnvironmentWithOptions(nullptr, nullptr, ...)`.
- This targets installed runtime discovery (Evergreen runtime model).
- Fixed Version runtime folders are not wired through plugin configuration.

Practical packaging checklist:

- Match runtime installer architecture to your app build architecture.
- Install WebView2 Runtime before first launch of the app.
- Keep the app-side error handling for `webViewUnavailable` as a fallback for
	machines where runtime installation fails or is blocked.


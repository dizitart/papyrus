# Conformance Tests

Papyrus now has two layers of conformance coverage:

- Contract coverage: pure Dart and package-level tests that validate the shared public API surface, request models, and controller behavior without a live backend.
- Live backend coverage: integration tests in `examples/papyrus_example/integration_test/` that exercise the real platform implementations on the selected Flutter device.

## Recommended Runner

Use the cross-host runner from the repository root:

```bash
dart run tool/run_platform_conformance.dart --device <flutter-device-id>
```

The runner executes:

1. The contract layer that `tool/check.sh` currently covers:
	- `packages/papyrus_platform_interface`: `flutter test`, `flutter analyze`
	- `packages/papyrus`: `flutter test`, `flutter analyze`
	- platform packages: `flutter analyze`
	- root acceptance test: `flutter test test/acceptance_test.dart`
2. `examples/papyrus_example/integration_test/papyrus_native_smoke_test.dart`
3. `examples/papyrus_example/integration_test/papyrus_public_api_conformance_test.dart`

Useful flags:

- `--skip-checks` to rerun only the live device-backed suites.
- `--skip-smoke` to skip the backend smoke suite.
- `--skip-api` to skip the public API conformance suite.
- `--native-macos-platform-view` to run the macOS example with `PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW=true`.

Examples:

```bash
dart run tool/run_platform_conformance.dart --device macos
dart run tool/run_platform_conformance.dart --device macos --native-macos-platform-view
dart run tool/run_platform_conformance.dart --device 4BC64162-0CFF-4C35-B60E-7B4A4EFF0770 --skip-checks
dart run tool/run_platform_conformance.dart --device emulator-5554 --skip-checks
dart run tool/run_platform_conformance.dart --device linux --skip-checks
dart run tool/run_platform_conformance.dart --device windows --skip-checks
```

Use `flutter devices` to list available device ids before running the script.

## Live Coverage Matrix

The live suites currently cover these backend behaviors:

- Intercepted main-document loading and resource callbacks.
- Navigation policy enforcement through both static backend policy and host-driven `onNavigationRequest` callbacks on supported backends.
- Navigation APIs and history behavior where the backend exposes a back/forward stack.
- `currentUri()` and progress checks on intercepted navigations.
- Text-selection helpers: `selectedText()`, `copySelection()`, and `quoteSelection()`.
- Snapshot support.
- Print support on backends where `printDocument` completes non-interactively under `flutter test`.
- Cache and storage clearing.
- File-backed loading metadata on iOS, macOS, Linux, and Windows.

Recent live validation:

- The text-selection helper scenario and the full public API conformance suite were rerun successfully on `macos`, the iOS simulator `4BC64162-0CFF-4C35-B60E-7B4A4EFF0770`, and the Android emulator `emulator-5554`.
- Focused navigation-policy scenarios now pass on `macos`, the iOS simulator `4BC64162-0CFF-4C35-B60E-7B4A4EFF0770`, and the Android emulator `emulator-5554`, including blocked scripted navigation and host-blocked `onNavigationRequest` redirects.

## Known Gaps

- Android `loadFile` is still covered contractually through the controller/package tests, but the live `flutter test` path for file-backed follow-up assertions is not stable enough yet to keep in the portable backend suite. The public API conformance integration file skips that live file-metadata slice on Android for now.
- macOS print capability is still reported and covered contractually, but the live `printDocument` invocation is skipped in the portable suite because `WKWebView.printView` enters an interactive print flow under `flutter test`.
- `loadData` remains contract-tested only. Native parity for live byte-data loading is not finished across all backends yet.
- Linux and Windows have the new selected-text backend hooks, but that live interaction slice still needs host-native validation on those machines.
- Linux and Windows now reject file-backed loads when `allowFileAccess` is false and route navigation through native pre-commit policy hooks, but those navigation and storage/privacy slices still need host-native live validation on Linux and Windows.

## Host Notes

- macOS: run once with `--device macos` and again with `--device macos --native-macos-platform-view` if you want both overlay and native platform-view paths.
- iOS: boot the target simulator first, then pass its device id.
- Android: boot an emulator or connect a device first, then pass its device id.
- Linux and Windows: use `linux` or `windows` as the device id on the corresponding host machine.


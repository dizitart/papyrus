# Papyrus Testbed

This app is a Papyrus-focused manual testbed for validating HTML rendering and
MIME email extraction behavior.

## What this testbed does

- Raw HTML/CSS mode
	- Paste raw HTML (with inline or embedded CSS).
	- Render directly in Papyrus.
- Raw MIME email mode
	- Paste a full MIME message.
	- Extracts `text/html` first.
	- Falls back to `text/plain` rendered as HTML when `text/html` is missing.
	- If MIME contains `text/css` parts, their CSS is injected into the rendered
		HTML.
- Shared viewport emulation
	- Mobile: `390 x 844`
	- Tablet: `768 x 1024`
	- Desktop: `1440 x 900`
	- The selected viewport is applied to Papyrus preview in both tabs.

## UI model

- One screen with two tabs:
	- `Raw HTML + CSS`
	- `Raw MIME Email`
- Each tab has:
	- Left pane: input editor + action buttons
	- Right pane: Papyrus preview panel
- Responsive behavior:
	- Wide layouts use side-by-side panes.
	- Narrow layouts stack editor and preview vertically.

## MIME extraction behavior implemented

- Supports multipart parsing using MIME boundaries.
- Supports body decoding for:
	- `base64`
	- `quoted-printable`
	- unencoded text
- Honors charset when available (fallbacks to UTF-8/Latin-1).
- Selection policy:
	- Prefer first `text/html` part.
	- Else fallback to first `text/plain` part.
	- Else report extraction error.

## Platform code changes made

- No platform runner files were modified in:
	- `android/`
	- `ios/`
	- `macos/`
	- `linux/`
	- `windows/`
	- `web/`
- Reason:
	- Papyrus plugin integration for this testbed is done at Flutter/Dart layer
		by adding the package dependency and using `PapyrusView` in `lib/main.dart`.
	- No platform-specific bootstrap code changes were required for this update.

## App code changes made

- Updated dependency setup in `pubspec.yaml`:
	- Added local path dependency on `papyrus`.
- Replaced template app in `lib/main.dart` with:
	- Papyrus testbed shell and tabbed UI.
	- Viewport selector (mobile/tablet/desktop).
	- Raw HTML renderer flow.
	- Raw MIME parser + extractor flow.
	- Papyrus preview surface with viewport framing.
- Desktop preview scrolling adjustment:
	- Added an explicit shared `ScrollController` for the desktop preview
		`Scrollbar` and `SingleChildScrollView` pairing.
	- Reason: avoids Flutter desktop assertion on Windows,
		`Scrollbar's ScrollController has no ScrollPosition attached`.

## Run locally

From this folder:

```bash
flutter pub get
flutter run
```

## Notes

- This app intentionally renders extracted HTML as-is (no sanitization).
- For production email rendering, MIME parsing and sanitization policies should
	be handled by the host application pipeline.
- For macOS apps, add the network client entitlement in both Debug and Release
	profiles:
	- `macos/Runner/DebugProfile.entitlements`
	- `macos/Runner/Release.entitlements`
	
	```xml
	<key>com.apple.security.network.client</key>
	<true/>
	```

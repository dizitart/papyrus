# Security

Papyrus defaults are conservative:

- JavaScript is disabled.
- Popups are disabled.
- File access and universal file URL access are disabled.
- Mixed content is blocked where the native engine supports it.
- Device permissions are denied or surfaced to the host app.
- Navigation is intercepted.
- Downloads are surfaced to the host app.
- Cookies and local storage are blocked in strict profiles.

Papyrus does not sanitize HTML or CSS. Applications that render untrusted
content must sanitize before passing content to Papyrus.


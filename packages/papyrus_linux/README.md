# papyrus_linux

Linux WebKitGTK implementation package for Papyrus.

Linux distributions must provide WebKitGTK development/runtime packages. The
implementation reports capability differences and dependency diagnostics instead
of silently pretending unsupported behavior is available.

Linux uses the shared desktop overlay model rather than a Flutter platform
view. `PapyrusView` lays out a Flutter placeholder and the plugin hosts the
WebKitGTK view inside a `GtkOverlay`/`GtkFixed` container positioned through
`setViewport`.

## Linux packaging dependencies

Papyrus probes for `webkit2gtk-4.1` at build and link time, falling back to
`webkit2gtk-4.0` if 4.1 is not present. GTK 3 (`gtk+-3.0`) is required by
both paths and is present by default on major desktop distributions.

| Distribution | webkit2gtk 4.1 | webkit2gtk 4.0 (fallback) |
|---|---|---|
| Ubuntu 22.04 LTS (Jammy) / Debian 12 | `libwebkit2gtk-4.1-0` | `libwebkit2gtk-4.0-0` |
| Ubuntu 24.04 LTS (Noble) | `libwebkit2gtk-4.1-0` | — |
| Fedora 39+ | `webkit2gtk4.1` | `webkit2gtk3` |
| openSUSE Tumbleweed | `libwebkit2gtk3-4_1-0` | `libwebkit2gtk3-0` |
| Arch Linux | `webkit2gtk-4.1` | `webkit2gtk` |

Install on Ubuntu 22.04 / 24.04:

```sh
sudo apt-get install libwebkit2gtk-4.1-0
```

Install on Fedora 39+:

```sh
sudo dnf install webkit2gtk4.1
```

Install on Arch Linux:

```sh
sudo pacman -S webkit2gtk-4.1
```

### AppImage / Snap / Flatpak notes

- **AppImage**: Bundle the host distribution's `libwebkit2gtk-4.1.so.0` and
  its transitive dependencies using a tool such as `linuxdeploy` with the GTK
  plugin. Test against the oldest target distribution.
- **Snap**: Declare the `desktop` and `desktop-legacy` interface plugs; GTK and
  WebKitGTK are provided by the `gnome` or `kde-neon` content snaps and do not
  need to be bundled manually.
- **Flatpak**: Include `org.gnome.Platform` (or equivalent) as a runtime
  extension; WebKitGTK is part of that runtime.

WebKitGTK must be installed or available through the container runtime before
the app starts. If it is absent, Flutter will fail to load the plugin DSO at
startup before Papyrus can surface a `webViewUnavailable` error.


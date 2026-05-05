# papyrus_linux

Linux WebKitGTK implementation package for Papyrus.

Linux distributions must provide WebKitGTK development/runtime packages. The
implementation reports capability differences and dependency diagnostics instead
of silently pretending unsupported behavior is available.

Linux uses the shared desktop overlay model rather than a Flutter platform
view. `PapyrusView` lays out a Flutter placeholder and the plugin hosts the
WebKitGTK view inside a `GtkOverlay`/`GtkFixed` container positioned through
`setViewport`.


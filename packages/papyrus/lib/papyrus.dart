/// Public API for the Papyrus secure, policy-driven WebView for Flutter.
///
/// Exported symbols include:
/// - [PapyrusController] for programmatic webview control
/// - [PapyrusView] for embedding the webview in Flutter widgets
/// - Shared configuration, events, requests, and policies from
///   `papyrus_platform_interface`
library;

export 'package:papyrus_platform_interface/papyrus_platform_interface.dart';

export 'src/papyrus_controller.dart';
export 'src/papyrus_view.dart';

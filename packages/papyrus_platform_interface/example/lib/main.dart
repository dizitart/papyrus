// Example for papyrus_platform_interface.
//
// This package defines the platform interface contracts used by Papyrus.
// For a complete runnable example, see the main `papyrus` package:
// https://pub.dev/packages/papyrus

import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';

void main() {
  // Build a locked-down configuration for secure HTML document viewing.
  const config = PapyrusConfiguration(
    security: PapyrusSecurityPolicy(allowJavaScript: false),
    navigation: PapyrusNavigationPolicy(
      defaultDecision: PapyrusNavigationDecision.block,
    ),
    resources: PapyrusResourcePolicy(
      remoteResources: PapyrusRemoteResourceMode.block,
    ),
  );

  // Load an HTML document using the platform interface.
  final request = PapyrusHtmlRequest(
    html: '<h1>Hello, Papyrus!</h1>',
    metadata: const PapyrusContentMetadata(
      contentType: 'text/html',
      source: 'local',
    ),
  );

  request.validate();

  // ignore: avoid_print
  print('Config: $config, Request type: ${request.type}');
}

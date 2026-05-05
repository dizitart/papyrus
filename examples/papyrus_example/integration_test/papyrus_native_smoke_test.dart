import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/papyrus.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native Papyrus platform loads HTML and reports capabilities', (
    tester,
  ) async {
    final controller = PapyrusController.create();

    final capabilities = await controller.getCapabilities();
    expect(capabilities.supportsDarkMode, isA<bool>());

    await controller.loadHtmlString(
      '<!doctype html><html><body><h1>Papyrus</h1></body></html>',
      baseUri: Uri.parse('papyrus-resource://integration.local/'),
    );

    final progress = await controller.estimatedProgress();
    expect(progress, greaterThanOrEqualTo(0));

    await controller.stopLoading();
    await controller.dispose();
  });

  testWidgets('strict defaults block script-oriented profile by default', (
    tester,
  ) async {
    final config = PapyrusProfiles.lockedDown();

    expect(config.security.allowJavaScript, isFalse);
    expect(config.javascript.mode, PapyrusJavaScriptMode.disabled);
    expect(config.navigation.defaultDecision, PapyrusNavigationDecision.block);
    expect(config.resources.remoteResources, PapyrusRemoteResourceMode.block);
  });
}

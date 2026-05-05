import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/papyrus.dart';

const MethodChannel _macosChannel = MethodChannel('dev.papyrus.papyrus_macos');
const String _overlaySmokeHtml = '''
<!doctype html>
<html>
  <head><title>Papyrus overlay smoke</title></head>
  <body style="margin:0;background:#155eef;color:white;font:24px -apple-system,sans-serif">
    <main style="height:220px;display:grid;place-items:center">
      <strong>Papyrus overlay smoke</strong>
    </main>
  </body>
</html>
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS desktop overlay attaches and renders HTML', (
    tester,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    const useNativePlatformView = bool.fromEnvironment(
      'PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW',
    );
    expect(
      useNativePlatformView,
      isFalse,
      reason:
          'Run without PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW so the default '
          'desktop overlay path is exercised on macOS.',
    );

    final controller = PapyrusController.create();
    addTearDown(() async => controller.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 220,
              child: PapyrusView(
                controller: controller,
                configuration: const PapyrusConfiguration(
                  security: PapyrusSecurityPolicy(allowJavaScript: true),
                  platform: PapyrusPlatformOptions(
                    hardwareAcceleration:
                        PapyrusHardwareAccelerationMode.software,
                  ),
                ),
                initialRequest: const PapyrusHtmlRequest(
                  html: _overlaySmokeHtml,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final state = await _waitForOverlay(tester);
    expect(state['overlayAttached'], isTrue);
    expect(state['webViewAttached'], isTrue);
    expect(state['visible'], isTrue);
    expect((state['width'] as num?)?.toDouble(), greaterThanOrEqualTo(360));
    expect((state['height'] as num?)?.toDouble(), greaterThanOrEqualTo(220));

    await controller.loadHtmlString(_overlaySmokeHtml);

    final snapshot = await _waitForSnapshot(tester, controller);
    expect(snapshot.length, greaterThan(0));
    final image = await _decodeSnapshot(snapshot);
    addTearDown(image.dispose);
    expect(image.width, greaterThanOrEqualTo(360));
    expect(image.height, greaterThanOrEqualTo(220));
  });

  testWidgets('example-style macOS overlay renders visible content', (
    tester,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }

    final controller = PapyrusController.create();
    addTearDown(() async => controller.dispose());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Papyrus Example')),
          body: Column(
            children: [
              SegmentedButton<PapyrusConfiguration>(
                segments: const [
                  ButtonSegment<PapyrusConfiguration>(
                    value: PapyrusConfiguration(
                      resources: PapyrusResourcePolicy(
                        remoteResources: PapyrusRemoteResourceMode.askHostApp,
                      ),
                      navigation: PapyrusNavigationPolicy(
                        defaultDecision:
                            PapyrusNavigationDecision.openExternally,
                      ),
                    ),
                    label: Text('Docs'),
                  ),
                  ButtonSegment<PapyrusConfiguration>(
                    value: PapyrusConfiguration(
                      navigation: PapyrusNavigationPolicy(
                        defaultDecision:
                            PapyrusNavigationDecision.openExternally,
                        requireUserGestureForExternalOpen: true,
                        allowMainFrameNavigation: false,
                        allowSubFrameNavigation: false,
                      ),
                      resources: PapyrusResourcePolicy(
                        remoteResources: PapyrusRemoteResourceMode.block,
                      ),
                      javascript: PapyrusJavaScriptPolicy(
                        mode: PapyrusJavaScriptMode.disabled,
                      ),
                      storage: PapyrusStoragePolicy(
                        cookies: PapyrusCookiePolicy.block,
                        localStorage: PapyrusStorageMode.disabled,
                        ephemeral: true,
                      ),
                      display: PapyrusDisplayPolicy(autoHeight: true),
                    ),
                    label: Text('Email'),
                  ),
                ],
                selected: {PapyrusProfiles.documentViewer()},
                onSelectionChanged: (_) {},
              ),
              Expanded(
                child: PapyrusView(
                  controller: controller,
                  configuration: PapyrusProfiles.documentViewer(),
                  initialRequest: const PapyrusHtmlRequest(
                    html: '<h1>Papyrus</h1><p>Controlled HTML content.</p>',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final state = await _waitForOverlay(tester);
    expect(state['overlayAttached'], isTrue);
    expect(state['webViewAttached'], isTrue);
    expect(state['visible'], isTrue);
    final snapshot = await _waitForSnapshot(tester, controller);
    expect(snapshot.length, greaterThan(0));
    final image = await _decodeSnapshot(snapshot);
    addTearDown(image.dispose);
    final hasVisibleContent = await _containsVisibleNonWhitePixel(image);
    if (!hasVisibleContent) {
      throw TestFailure('overlayState=$state');
    }
  });
}

Future<Map<String, Object?>> _waitForOverlay(WidgetTester tester) async {
  Map<String, Object?> state = const {};
  for (var attempt = 0; attempt < 30; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    state =
        await _macosChannel.invokeMapMethod<String, Object?>(
          'debugOverlayState',
        ) ??
        const {};
    final width = (state['width'] as num?)?.toDouble() ?? 0;
    final height = (state['height'] as num?)?.toDouble() ?? 0;
    if (state['visible'] == true && width >= 360 && height >= 220) {
      break;
    }
  }
  return state;
}

Future<Uint8List> _waitForSnapshot(
  WidgetTester tester,
  PapyrusController controller,
) async {
  var snapshot = Uint8List(0);
  for (var attempt = 0; attempt < 30; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    snapshot = await controller.captureSnapshot();
    if (snapshot.isNotEmpty) {
      break;
    }
  }
  return snapshot;
}

Future<ui.Image> _decodeSnapshot(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<bool> _containsVisibleNonWhitePixel(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    return false;
  }
  final bytes = byteData.buffer.asUint8List();
  for (var offset = 0; offset <= bytes.length - 4; offset += 4) {
    final red = bytes[offset];
    final green = bytes[offset + 1];
    final blue = bytes[offset + 2];
    final alpha = bytes[offset + 3];
    if (alpha > 0 && (red < 245 || green < 245 || blue < 245)) {
      return true;
    }
  }
  return false;
}

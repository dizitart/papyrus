import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/papyrus.dart';

const String _smokeHtml = '''
<!doctype html>
<html>
  <head><title>Papyrus smoke</title></head>
  <body style="margin:0;background:#155eef;color:white;font:24px -apple-system,sans-serif">
    <main style="height:220px;display:grid;place-items:center">
      <strong>Papyrus smoke</strong>
    </main>
  </body>
</html>
''';

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

  testWidgets('desktop overlay Papyrus view attaches on Windows and Linux', (
    tester,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.windows &&
        defaultTargetPlatform != TargetPlatform.linux) {
      return;
    }

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
                ),
                initialRequest: const PapyrusHtmlRequest(html: _smokeHtml),
              ),
            ),
          ),
        ),
      ),
    );

    final state = await _waitForOverlayState(tester);
    expect(state['overlayAttached'], isTrue);
    expect(state['webViewAttached'], isTrue);
    expect(state['visible'], isTrue);
    expect((state['width'] as num?)?.toDouble(), greaterThanOrEqualTo(360));
    expect((state['height'] as num?)?.toDouble(), greaterThanOrEqualTo(220));
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

  testWidgets('mobile Papyrus native view renders visible content', (
    tester,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }

    final controller = PapyrusController.create();
    final pageFinished = Completer<void>();
    addTearDown(() async {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await controller.dispose();
        return;
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await controller.dispose();
    });

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
                ),
                initialRequest: const PapyrusHtmlRequest(html: _smokeHtml),
                onPageFinished: (_) {
                  if (!pageFinished.isCompleted) {
                    pageFinished.complete();
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final hasVisibleContent = switch (defaultTargetPlatform) {
      TargetPlatform.android => await _waitForAndroidNativeView(tester),
      TargetPlatform.iOS => await _waitForIosVisibleContent(
        tester,
        controller,
        pageFinished,
      ),
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.fuchsia => false,
    };
    expect(hasVisibleContent, isTrue);
  });

  testWidgets('Papyrus resource interception serves an intercepted document', (
    tester,
  ) async {
    final controller = PapyrusController.create();
    final documentRequested = Completer<void>();
    PapyrusResourceRequest? interceptedRequest;
    final interceptedDocumentUri =
        defaultTargetPlatform == TargetPlatform.android
        ? Uri.parse('https://integration.local/document.html')
        : Uri.parse('papyrus-resource://integration.local/document.html');
    addTearDown(() async {
      if (defaultTargetPlatform != TargetPlatform.android) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      await controller.dispose();
    });

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
                ),
                initialRequest: PapyrusUriRequest(uri: interceptedDocumentUri),
                onResourceRequest: (request) async {
                  if (request.uri == interceptedDocumentUri) {
                    interceptedRequest = request;
                    if (!documentRequested.isCompleted) {
                      documentRequested.complete();
                    }
                    return PapyrusRespondWithResource(
                      PapyrusResourceResponse(
                        bytes: Uint8List.fromList(utf8.encode(_smokeHtml)),
                        mimeType: 'text/html',
                      ),
                    );
                  }
                  return const PapyrusBlockResource();
                },
              ),
            ),
          ),
        ),
      ),
    );

    await _waitForCompleter(tester, documentRequested);
    expect(documentRequested.isCompleted, isTrue);
    expect(interceptedRequest, isNotNull);
    expect(interceptedRequest!.method, 'GET');
    expect(interceptedRequest!.resourceType, PapyrusResourceType.document);
    expect(interceptedRequest!.uri, interceptedDocumentUri);

    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final hasStyledContent = await _waitForVisibleSnapshot(
        tester,
        controller,
      );
      expect(hasStyledContent, isTrue);
    }
  });
}

Future<Map<String, Object?>> _waitForOverlayState(WidgetTester tester) async {
  final channel = _overlayDebugChannelForPlatform();
  expect(channel, isNotNull);

  Map<String, Object?> state = const {};
  for (var attempt = 0; attempt < 30; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    state =
        await channel!.invokeMapMethod<String, Object?>('debugOverlayState') ??
        const {};
    final width = (state['width'] as num?)?.toDouble() ?? 0;
    final height = (state['height'] as num?)?.toDouble() ?? 0;
    if (state['visible'] == true && width >= 360 && height >= 220) {
      break;
    }
  }
  return state;
}

MethodChannel? _overlayDebugChannelForPlatform() {
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return const MethodChannel('dev.papyrus.papyrus_windows');
    case TargetPlatform.linux:
      return const MethodChannel('dev.papyrus.papyrus_linux');
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
    case TargetPlatform.fuchsia:
      return null;
  }
}

Future<void> _waitForPageFinished(
  WidgetTester tester,
  Completer<void> pageFinished,
) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    if (pageFinished.isCompleted) {
      await pageFinished.future;
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForCompleter(
  WidgetTester tester,
  Completer<void> completer,
) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    if (completer.isCompleted) {
      await completer.future;
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<bool> _waitForVisibleSnapshot(
  WidgetTester tester,
  PapyrusController controller,
) async {
  for (var attempt = 0; attempt < 20; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    final snapshot = await controller.captureSnapshot();
    if (snapshot.isEmpty) {
      continue;
    }

    final image = await _decodeSnapshot(snapshot);
    final hasVisibleContent = await _containsVisibleNonWhitePixel(image);
    image.dispose();
    if (hasVisibleContent) {
      return true;
    }
  }
  return false;
}

Future<bool> _waitForIosVisibleContent(
  WidgetTester tester,
  PapyrusController controller,
  Completer<void> pageFinished,
) async {
  await _waitForPageFinished(tester, pageFinished);
  return _waitForVisibleSnapshot(tester, controller);
}

Future<bool> _waitForAndroidNativeView(WidgetTester tester) async {
  if (tester.takeException() case final Object error?) {
    throw TestFailure('android platform view threw: $error');
  }
  return find.byType(AndroidView).evaluate().isNotEmpty;
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

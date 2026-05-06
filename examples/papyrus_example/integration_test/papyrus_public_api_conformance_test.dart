import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:papyrus/papyrus.dart';

const String _documentAHtml = '''
<!doctype html>
<html>
  <head><title>Document A</title></head>
  <body style="margin:0;background:#0f172a;color:white;font:24px -apple-system,sans-serif">
    <main style="height:220px;display:grid;place-items:center">Document A</main>
  </body>
</html>
''';

const String _documentBHtml = '''
<!doctype html>
<html>
  <head><title>Document B</title></head>
  <body style="margin:0;background:#155eef;color:white;font:24px -apple-system,sans-serif">
    <main style="height:220px;display:grid;place-items:center">Document B</main>
  </body>
</html>
''';

const String _fileDocumentHtml = '''
<!doctype html>
<html>
  <head><title>File Document</title></head>
  <body style="margin:0;background:#0f766e;color:white;font:24px -apple-system,sans-serif">
    <main style="height:220px;display:grid;place-items:center">File Document</main>
  </body>
</html>
''';

const String _selectionHtml = '''
<!doctype html>
<html>
  <head>
    <title>Selection Document</title>
    <script>
      window.addEventListener('load', function () {
        const target = document.getElementById('selection-target');
        if (!target || !window.getSelection) {
          return;
        }
        const selection = window.getSelection();
        const range = document.createRange();
        range.selectNodeContents(target);
        selection.removeAllRanges();
        selection.addRange(range);
      });
    </script>
  </head>
  <body style="margin:0;font:20px -apple-system,sans-serif">
    <p id="selection-target">Papyrus selection text</p>
  </body>
</html>
''';

const PapyrusConfiguration _conformanceConfiguration = PapyrusConfiguration(
  security: PapyrusSecurityPolicy(allowJavaScript: true, allowFileAccess: true),
  resources: PapyrusResourcePolicy(
    remoteResources: PapyrusRemoteResourceMode.askHostApp,
  ),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('public API conformance for intercepted documents and history', (
    tester,
  ) async {
    final controller = PapyrusController.create();
    final resourceRequests = <PapyrusResourceRequest>[];
    final documentAUri = _platformDocumentUri('history-a.html');
    final documentBUri = _platformDocumentUri('history-b.html');
    final responses = <Uri, String>{
      documentAUri: _documentAHtml,
      documentBUri: _documentBHtml,
    };

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _withStepTimeout(controller.dispose(), 'controller.dispose');
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
                configuration: _conformanceConfiguration,
                initialRequest: PapyrusUriRequest(uri: documentAUri),
                onResourceRequest: (request) async {
                  resourceRequests.add(request);
                  final html = responses[request.uri];
                  if (html == null) {
                    return const PapyrusBlockResource();
                  }
                  return PapyrusRespondWithResource(
                    PapyrusResourceResponse(
                      bytes: Uint8List.fromList(utf8.encode(html)),
                      mimeType: 'text/html',
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final capabilities = await controller.getCapabilities();
    expect(capabilities.supportsDarkMode, isA<bool>());
    await _waitForCurrentUri(tester, controller, documentAUri);
    await _waitForCondition(
      tester,
      () => resourceRequests.any((request) => request.uri == documentAUri),
      'Timed out waiting for intercepted request for $documentAUri',
    );

    expect(
      resourceRequests.any(
        (request) =>
            request.uri == documentAUri &&
            request.resourceType == PapyrusResourceType.document &&
            request.isMainFrame,
      ),
      isTrue,
    );
    expect(await controller.currentUri(), documentAUri);
    expect(await controller.estimatedProgress(), greaterThanOrEqualTo(0));

    await controller.loadUri(documentBUri);
    await _waitForCurrentUri(tester, controller, documentBUri);

    final canGoBack = await controller.canGoBack();
    await controller.goBack();
    if (canGoBack) {
      await _waitForCurrentUri(tester, controller, documentAUri);
    }

    final canGoForward = await controller.canGoForward();

    await controller.goForward();
    if (canGoBack && canGoForward) {
      await _waitForCurrentUri(tester, controller, documentBUri);
    }

    await controller.reload();
    await tester.pump(const Duration(milliseconds: 250));
    await controller.stopLoading();

    expect(resourceRequests, isNotEmpty);
  });

  testWidgets('public API conformance for file loading metadata', (
    tester,
  ) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return;
    }

    final harness = await _createFileConformanceHarness(tester);
    final controller = harness.controller;

    expect(harness.loadedUri, isNotNull);
    expect(harness.loadedUri?.scheme, 'file');

    final contentSize = await _waitForPositiveContentSize(tester, controller);
    expect(contentSize.width, greaterThan(0));
    expect(contentSize.height, greaterThan(0));
  });

  testWidgets('public API conformance for snapshot support', (tester) async {
    final harness = await _createHtmlConformanceHarness(tester);
    final controller = harness.controller;
    final capabilities = harness.capabilities;

    if (capabilities.supportsSnapshot) {
      final snapshot = await _withStepTimeout(
        controller.captureSnapshot(),
        'controller.captureSnapshot',
      );
      expect(snapshot, isNotEmpty);
    } else {
      expect(
        () => controller.captureSnapshot(),
        throwsA(
          isA<PapyrusException>().having(
            (error) => error.code,
            'code',
            PapyrusErrorCode.unsupportedPlatformFeature,
          ),
        ),
      );
    }
  });

  testWidgets('public API conformance for text selection helpers', (tester) async {
    final controller = PapyrusController.create();

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _withStepTimeout(controller.dispose(), 'controller.dispose');
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
                configuration: _conformanceConfiguration,
                initialRequest: const PapyrusHtmlRequest(html: _selectionHtml),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final selectedText = await _waitForSelectedText(
      tester,
      controller,
      'Papyrus selection text',
    );
    expect(selectedText, 'Papyrus selection text');
    expect(
      await controller.quoteSelection(prefix: '> '),
      '> Papyrus selection text',
    );

    await controller.copySelection();
    final clipboardData = await Clipboard.getData('text/plain');
    expect(clipboardData?.text, 'Papyrus selection text');
  });

  testWidgets('public API conformance for print and storage maintenance', (
    tester,
  ) async {
    late final PapyrusController controller;
    late final PapyrusPlatformCapabilities capabilities;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final harness = await _createHtmlConformanceHarness(tester);
      controller = harness.controller;
      capabilities = harness.capabilities;
    } else {
      final harness = await _createFileConformanceHarness(tester);
      controller = harness.controller;
      capabilities = harness.capabilities;
    }

    if (capabilities.supportsPrint &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      await _withStepTimeout(
        controller.printDocument(
          options: const PapyrusPrintOptions(jobName: 'Papyrus Conformance'),
        ),
        'controller.printDocument',
      );
    } else if (!capabilities.supportsPrint) {
      expect(
        () => controller.printDocument(
          options: const PapyrusPrintOptions(jobName: 'Papyrus Conformance'),
        ),
        throwsA(
          isA<PapyrusException>().having(
            (error) => error.code,
            'code',
            PapyrusErrorCode.unsupportedPlatformFeature,
          ),
        ),
      );
    }

    await _withStepTimeout(controller.clearCache(), 'controller.clearCache');
    await _withStepTimeout(
      controller.clearStorage(const PapyrusStorageClearOptions()),
      'controller.clearStorage',
    );
  });
}

class _FileConformanceHarness {
  const _FileConformanceHarness({
    required this.controller,
    required this.capabilities,
    required this.loadedUri,
  });

  final PapyrusController controller;
  final PapyrusPlatformCapabilities capabilities;
  final Uri? loadedUri;
}

class _HtmlConformanceHarness {
  const _HtmlConformanceHarness({
    required this.controller,
    required this.capabilities,
  });

  final PapyrusController controller;
  final PapyrusPlatformCapabilities capabilities;
}

Future<_FileConformanceHarness> _createFileConformanceHarness(
  WidgetTester tester,
) async {
  final controller = PapyrusController.create();
  final tempDirectory = await Directory.systemTemp.createTemp('papyrus_api_');
  final file = File('${tempDirectory.path}/document.html');
  await file.writeAsString(_fileDocumentHtml);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _withStepTimeout(controller.dispose(), 'controller.dispose');
    if (await tempDirectory.exists()) {
      await _withStepTimeout(
        tempDirectory.delete(recursive: true),
        'tempDirectory.delete',
      );
    }
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
              configuration: _conformanceConfiguration,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final capabilities = await controller.getCapabilities();
  await tester.pump(const Duration(milliseconds: 300));

  await _withStepTimeout(controller.loadFile(file.path), 'controller.loadFile');
  await _waitForUriScheme(tester, controller, 'file');
  final loadedUri = await _withStepTimeout(
    controller.currentUri(),
    'controller.currentUri',
  );

  return _FileConformanceHarness(
    controller: controller,
    capabilities: capabilities,
    loadedUri: loadedUri,
  );
}

Future<_HtmlConformanceHarness> _createHtmlConformanceHarness(
  WidgetTester tester,
) async {
  final controller = PapyrusController.create();

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _withStepTimeout(controller.dispose(), 'controller.dispose');
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
              configuration: _conformanceConfiguration,
              initialRequest: const PapyrusHtmlRequest(html: _documentAHtml),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  final capabilities = await controller.getCapabilities();
  await tester.pump(const Duration(milliseconds: 500));

  return _HtmlConformanceHarness(
    controller: controller,
    capabilities: capabilities,
  );
}

Uri _platformDocumentUri(String path) {
  return defaultTargetPlatform == TargetPlatform.android
      ? Uri.parse('https://integration.local/$path')
      : Uri.parse('papyrus-resource://integration.local/$path');
}

Future<void> _waitForCurrentUri(
  WidgetTester tester,
  PapyrusController controller,
  Uri expected,
) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    if (await controller.currentUri() == expected) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  throw TestFailure('Timed out waiting for currentUri=$expected');
}

Future<void> _waitForUriScheme(
  WidgetTester tester,
  PapyrusController controller,
  String scheme,
) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    if ((await controller.currentUri())?.scheme == scheme) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  throw TestFailure('Timed out waiting for currentUri scheme=$scheme');
}

Future<void> _waitForCondition(
  WidgetTester tester,
  bool Function() condition,
  String errorMessage,
) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    if (condition()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  throw TestFailure(errorMessage);
}

Future<PapyrusContentSize> _waitForPositiveContentSize(
  WidgetTester tester,
  PapyrusController controller,
) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    final contentSize = await _withStepTimeout(
      controller.getContentSize(),
      'controller.getContentSize',
    );
    if (contentSize.width > 0 && contentSize.height > 0) {
      return contentSize;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  throw TestFailure('Timed out waiting for positive content size');
}

Future<String?> _waitForSelectedText(
  WidgetTester tester,
  PapyrusController controller,
  String expected,
) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    final value = await _withStepTimeout(
      controller.selectedText(),
      'controller.selectedText',
    );
    if (value == expected) {
      return value;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }

  throw TestFailure('Timed out waiting for selectedText=$expected');
}

Future<T> _withStepTimeout<T>(Future<T> future, String label) {
  return future.timeout(
    const Duration(seconds: 10),
    onTimeout: () => throw TestFailure('Timed out during $label'),
  );
}

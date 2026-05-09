import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:papyrus/papyrus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller delegates load and state operations to platform', () async {
    final platform = RecordingPapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    await controller.loadHtmlString('<h1>Hello</h1>');
    await controller.loadUri(Uri.parse('https://example.com'));
    await controller.loadFile('/tmp/message.html');
    await controller.loadData(Uint8List.fromList([60, 112, 62]), 'text/html');
    await controller.reload();
    await controller.stopLoading();
    await controller.clearCache();
    await controller.clearStorage(const PapyrusStorageClearOptions());
    await controller.dispose();

    expect(platform.loaded, hasLength(4));
    expect(platform.commands, [
      'reload',
      'stopLoading',
      'clearCache',
      'clearStorage',
      'dispose',
    ]);
  });

  testWidgets('PapyrusView creates controller and performs initial load', (
    tester,
  ) async {
    final platform = RecordingPapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();
    PapyrusController? created;

    await tester.pumpWidget(
      PapyrusView(
        controller: controller,
        initialRequest: const PapyrusHtmlRequest(html: '<p>Initial</p>'),
        onCreated: (value) => created = value,
      ),
    );
    await tester.pump();

    expect(created, same(controller));
    expect(platform.loaded.single, isA<PapyrusHtmlRequest>());
    expect(find.byType(SizedBox), findsNothing);
    expect(
      find.textContaining('Papyrus native WebView embedding is not available'),
      findsOneWidget,
    );
  });

  testWidgets('PapyrusView drives desktop overlay viewport surfaces', (
    tester,
  ) async {
    final platform = OverlayPapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 320,
          height: 180,
          child: PapyrusView(
            controller: controller,
            initialRequest: const PapyrusHtmlRequest(html: '<p>Overlay</p>'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(platform.created, isTrue);
    expect(platform.loaded.single, isA<PapyrusHtmlRequest>());
    expect(platform.viewports, isNotEmpty);
    expect(platform.viewports.last['visible'], isTrue);
    expect(platform.viewports.last['width'], 320);
    expect(platform.viewports.last['height'], 180);
    expect(
      find.textContaining('Papyrus native WebView embedding is not available'),
      findsNothing,
    );
  });

  testWidgets('PapyrusView desktop overlay settles after viewport sync', (
    tester,
  ) async {
    final platform = OverlayPapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    await tester.pumpWidget(
      SizedBox(
        width: 320,
        height: 180,
        child: PapyrusView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'PapyrusView waits for overlay viewport application before initial load',
    (tester) async {
      final platform = DelayedViewportOverlayPapyrusPlatform();
      PapyrusPlatform.instance = platform;
      final controller = PapyrusController.create();

      await tester.pumpWidget(
        SizedBox(
          width: 320,
          height: 180,
          child: PapyrusView(
            controller: controller,
            initialRequest: const PapyrusHtmlRequest(html: '<p>Overlay</p>'),
          ),
        ),
      );
      await tester.pump();

      expect(platform.viewports, isNotEmpty);
      expect(platform.loaded, isEmpty);

      platform.completeViewportSync();
      await tester.pump();

      expect(platform.loaded, hasLength(1));
      expect(platform.loaded.single, isA<PapyrusHtmlRequest>());
    },
  );

  testWidgets('PapyrusView reloads when the initial request changes', (
    tester,
  ) async {
    final platform = MethodSurfacePapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    await tester.pumpWidget(
      PapyrusView(
        controller: controller,
        initialRequest: const PapyrusHtmlRequest(html: '<p>First</p>'),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      PapyrusView(
        controller: controller,
        initialRequest: const PapyrusHtmlRequest(html: '<p>Second</p>'),
      ),
    );
    await tester.pump();

    expect(platform.loaded, hasLength(2));
    expect((platform.loaded.first as PapyrusHtmlRequest).html, '<p>First</p>');
    expect((platform.loaded.last as PapyrusHtmlRequest).html, '<p>Second</p>');
  });

  testWidgets('PapyrusView reapplies method-surface configuration changes', (
    tester,
  ) async {
    final platform = MethodSurfacePapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    await tester.pumpWidget(
      PapyrusView(
        controller: controller,
        configuration: PapyrusProfiles.documentViewer(),
        initialRequest: const PapyrusHtmlRequest(html: '<p>Config</p>'),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(
      PapyrusView(
        controller: controller,
        configuration: PapyrusProfiles.browserLike(),
        initialRequest: const PapyrusHtmlRequest(html: '<p>Config</p>'),
      ),
    );
    await tester.pump();

    expect(platform.createdConfigurations, hasLength(2));
    expect(
      platform.createdConfigurations.first.security.allowJavaScript,
      isFalse,
    );
    expect(
      platform.createdConfigurations.last.security.allowJavaScript,
      isTrue,
    );
    expect(platform.loaded, hasLength(2));
  });

  testWidgets('PapyrusView installs and clears the resource resolver', (
    tester,
  ) async {
    final platform = RecordingPapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    Future<PapyrusResourceDecision> handleResource(
      PapyrusResourceRequest request,
    ) async {
      return const PapyrusBlockResource();
    }

    await tester.pumpWidget(
      PapyrusView(controller: controller, onResourceRequest: handleResource),
    );

    expect(platform.resourceResolver, same(handleResource));
    expect(
      await platform.resourceResolver!(
        PapyrusResourceRequest(
          uri: Uri.parse('https://example.com/image.png'),
          method: 'GET',
          headers: const {},
          resourceType: PapyrusResourceType.image,
          isMainFrame: false,
        ),
      ),
      isA<PapyrusBlockResource>(),
    );

    await tester.pumpWidget(const SizedBox.shrink());

    expect(platform.resourceResolver, isNull);
  });

  testWidgets('PapyrusView installs and clears the navigation resolver', (
    tester,
  ) async {
    final platform = RecordingPapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    Future<PapyrusNavigationDecision> handleNavigation(
      PapyrusNavigationRequest request,
    ) async {
      return PapyrusNavigationDecision.openExternally;
    }

    await tester.pumpWidget(
      PapyrusView(
        controller: controller,
        onNavigationRequest: handleNavigation,
      ),
    );

    expect(platform.navigationResolver, same(handleNavigation));
    expect(
      await platform.navigationResolver!(
        PapyrusNavigationRequest(
          uri: Uri.parse('https://example.com'),
          isMainFrame: true,
          navigationType: PapyrusNavigationType.linkClicked,
          hasUserGesture: true,
        ),
      ),
      PapyrusNavigationDecision.openExternally,
    );

    await tester.pumpWidget(const SizedBox.shrink());

    expect(platform.navigationResolver, isNull);
  });

  test('unsupported snapshot surfaces structured platform error', () async {
    final platform = RecordingPapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

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
  });

  test('content size and auto-height unsupported errors are structured', () {
    final platform = RecordingPapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    expect(
      () => controller.getContentSize(),
      throwsA(
        isA<PapyrusException>().having(
          (error) => error.code,
          'code',
          PapyrusErrorCode.unsupportedPlatformFeature,
        ),
      ),
    );

    const display = PapyrusDisplayPolicy(
      autoHeight: true,
      minimumHeight: 100,
      maximumHeight: 600,
      zoomEnabled: false,
      textZoom: 1.2,
      measurement: PapyrusMeasurementPolicy(observeMutations: true),
    );

    expect(display.autoHeight, isTrue);
    expect(display.minimumHeight, 100);
    expect(display.maximumHeight, 600);
    expect(display.zoomEnabled, isFalse);
    expect(display.measurement.observeMutations, isTrue);
  });

  test(
    'controller delegates initialization, navigation, and optional APIs',
    () async {
      final platform = FeatureCompletePapyrusPlatform();
      PapyrusPlatform.instance = platform;
      final controller = PapyrusController.create();

      Future<PapyrusResourceDecision> handleResource(
        PapyrusResourceRequest request,
      ) async {
        return const PapyrusAllowResource();
      }

      await controller.initialize(
        configuration: PapyrusProfiles.documentViewer(),
      );
      await controller.setViewport(
        x: 1,
        y: 2,
        width: 320,
        height: 180,
        devicePixelRatio: 2,
        visible: true,
      );
      controller.setNavigationResolver((request) async {
        return PapyrusNavigationDecision.allow;
      });
      controller.setResourceResolver(handleResource);

      expect(platform.createdConfigurations, hasLength(1));
      expect(
        platform.createdConfigurations.single.resources.remoteResources,
        PapyrusRemoteResourceMode.askHostApp,
      );
      expect(platform.viewports.single['visible'], isTrue);
      expect(platform.navigationResolver, isNotNull);
      expect(platform.resourceResolver, same(handleResource));

      expect(await controller.canGoBack(), isTrue);
      expect(await controller.canGoForward(), isTrue);
      await controller.goBack();
      await controller.goForward();
      expect(
        await controller.currentUri(),
        Uri.parse('https://example.com/current'),
      );
      expect(await controller.title(), 'Papyrus Title');
      expect(await controller.estimatedProgress(), 0.75);
      expect(
        await controller.evaluateJavaScript('document.title'),
        'Papyrus Title',
      );
      expect(await controller.selectedText(), 'Quoted text');
      expect(await controller.quoteSelection(prefix: '> '), '> Quoted text');

      await controller.addJavaScriptChannel('bridge');
      await controller.removeJavaScriptChannel('bridge');
      await controller.printDocument(
        options: const PapyrusPrintOptions(jobName: 'Papyrus Test'),
      );

      final contentSize = await controller.getContentSize();
      expect(contentSize.width, 320);
      expect(contentSize.height, 180);

      final snapshot = await controller.captureSnapshot(
        options: const PapyrusSnapshotOptions(width: 320, height: 180),
      );
      expect(snapshot, [1, 2, 3]);

      final capabilities = await controller.getCapabilities();
      expect(capabilities.supportsSnapshot, isTrue);
      expect(capabilities.supportsResourceInterception, isTrue);

      expect(
        platform.commands,
        containsAll(['goBack', 'goForward', 'printDocument']),
      );
      expect(platform.addedJavaScriptChannels, ['bridge']);
      expect(platform.removedJavaScriptChannels, ['bridge']);
      expect(platform.lastEvaluatedJavaScript, 'document.title');
      expect(platform.lastPrintOptions?.jobName, 'Papyrus Test');
      expect(platform.lastSnapshotOptions?.width, 320);
      expect(platform.lastSnapshotOptions?.height, 180);
    },
  );

  testWidgets('controller copies the current selection to the clipboard', (
    tester,
  ) async {
    final platform = FeatureCompletePapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();
    MethodCall? clipboardCall;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          clipboardCall = call;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await controller.copySelection();

    expect(clipboardCall?.method, 'Clipboard.setData');
    expect(clipboardCall?.arguments, {'text': 'Quoted text'});
  });

  testWidgets('PapyrusView forwards page, progress, error, and size events', (
    tester,
  ) async {
    final platform = FeatureCompletePapyrusPlatform();
    PapyrusPlatform.instance = platform;
    final controller = PapyrusController.create();

    Uri? startedUri;
    Uri? finishedUri;
    double? progress;
    PapyrusErrorEvent? errorEvent;
    PapyrusContentSize? contentSize;

    await tester.pumpWidget(
      PapyrusView(
        controller: controller,
        onPageStarted: (event) => startedUri = event.uri,
        onPageFinished: (event) => finishedUri = event.uri,
        onProgressChanged: (event) => progress = event.progress,
        onError: (event) => errorEvent = event,
        onContentSizeChanged: (value) => contentSize = value,
      ),
    );

    platform.emit(
      PapyrusPageStartedEvent(uri: Uri.parse('https://example.com/start')),
    );
    platform.emit(
      PapyrusPageFinishedEvent(uri: Uri.parse('https://example.com/end')),
    );
    platform.emit(const PapyrusProgressEvent(0.5));
    platform.emit(
      const PapyrusErrorEvent(
        code: PapyrusErrorCode.networkFailed,
        message: 'network failed',
      ),
    );
    platform.emit(
      const PapyrusContentSizeChangedEvent(
        PapyrusContentSize(width: 300, height: 200),
      ),
    );
    await tester.pump();

    expect(startedUri, Uri.parse('https://example.com/start'));
    expect(finishedUri, Uri.parse('https://example.com/end'));
    expect(progress, 0.5);
    expect(errorEvent?.code, PapyrusErrorCode.networkFailed);
    expect(errorEvent?.message, 'network failed');
    expect(contentSize?.width, 300);
    expect(contentSize?.height, 200);
  });
}

class RecordingPapyrusPlatform extends PapyrusPlatform {
  final loaded = <PapyrusLoadRequest>[];
  final commands = <String>[];
  PapyrusNavigationResolver? navigationResolver;
  PapyrusResourceResolver? resourceResolver;
  final StreamController<PapyrusEvent> eventController =
      StreamController<PapyrusEvent>.broadcast();

  @override
  Stream<PapyrusEvent> get events => eventController.stream;

  void emit(PapyrusEvent event) => eventController.add(event);

  @override
  Future<void> load(PapyrusLoadRequest request) async {
    request.validate();
    loaded.add(request);
  }

  @override
  Future<void> reload() async => commands.add('reload');

  @override
  Future<void> stopLoading() async => commands.add('stopLoading');

  @override
  Future<void> clearCache() async => commands.add('clearCache');

  @override
  Future<void> clearStorage(PapyrusStorageClearOptions options) async {
    commands.add('clearStorage');
  }

  @override
  Future<void> dispose() async => commands.add('dispose');

  @override
  void setNavigationResolver(PapyrusNavigationResolver? resolver) {
    navigationResolver = resolver;
  }

  @override
  void setResourceResolver(PapyrusResourceResolver? resolver) {
    resourceResolver = resolver;
  }

  @override
  Future<Uint8List> captureSnapshot({PapyrusSnapshotOptions? options}) {
    throw const PapyrusException(
      PapyrusErrorCode.unsupportedPlatformFeature,
      'Snapshot is not supported by this platform.',
    );
  }

  @override
  Future<PapyrusContentSize> getContentSize() {
    throw const PapyrusException(
      PapyrusErrorCode.unsupportedPlatformFeature,
      'Content size is not supported by this platform.',
    );
  }
}

class FeatureCompletePapyrusPlatform extends RecordingPapyrusPlatform {
  final createdConfigurations = <PapyrusConfiguration>[];
  final viewports = <Map<String, Object?>>[];
  final addedJavaScriptChannels = <String>[];
  final removedJavaScriptChannels = <String>[];
  Uri? currentUriValue = Uri.parse('https://example.com/current');
  String? titleValue = 'Papyrus Title';
  double estimatedProgressValue = 0.75;
  bool canGoBackValue = true;
  bool canGoForwardValue = true;
  Object? evaluateJavaScriptValue = 'Papyrus Title';
  String? selectedTextValue = 'Quoted text';
  String? lastEvaluatedJavaScript;
  PapyrusSnapshotOptions? lastSnapshotOptions;
  PapyrusPrintOptions? lastPrintOptions;

  @override
  Future<void> create({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) async {
    createdConfigurations.add(configuration);
  }

  @override
  Future<void> setViewport({
    required double x,
    required double y,
    required double width,
    required double height,
    required double devicePixelRatio,
    required bool visible,
  }) async {
    viewports.add({
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'devicePixelRatio': devicePixelRatio,
      'visible': visible,
    });
  }

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<bool> canGoForward() async => canGoForwardValue;

  @override
  Future<void> goBack() async => commands.add('goBack');

  @override
  Future<void> goForward() async => commands.add('goForward');

  @override
  Future<Uri?> currentUri() async => currentUriValue;

  @override
  Future<String?> title() async => titleValue;

  @override
  Future<double> estimatedProgress() async => estimatedProgressValue;

  @override
  Future<Object?> evaluateJavaScript(String source) async {
    lastEvaluatedJavaScript = source;
    return evaluateJavaScriptValue;
  }

  @override
  Future<String?> selectedText() async => selectedTextValue;

  @override
  Future<void> addJavaScriptChannel(String name) async {
    addedJavaScriptChannels.add(name);
  }

  @override
  Future<void> removeJavaScriptChannel(String name) async {
    removedJavaScriptChannels.add(name);
  }

  @override
  Future<PapyrusContentSize> getContentSize() async {
    return const PapyrusContentSize(width: 320, height: 180);
  }

  @override
  Future<Uint8List> captureSnapshot({PapyrusSnapshotOptions? options}) async {
    lastSnapshotOptions = options;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> printDocument({PapyrusPrintOptions? options}) async {
    lastPrintOptions = options;
    commands.add('printDocument');
  }

  @override
  Future<PapyrusPlatformCapabilities> getCapabilities() async {
    return const PapyrusPlatformCapabilities(
      supportsResourceInterception: true,
      supportsVirtualSchemes: true,
      supportsEphemeralStorage: true,
      supportsPrint: true,
      supportsSnapshot: true,
      supportsAutoHeight: true,
      supportsDarkMode: true,
      supportsDownloadInterception: true,
      supportsPermissionInterception: true,
    );
  }
}

class OverlayPapyrusPlatform extends RecordingPapyrusPlatform {
  bool created = false;
  final viewports = <Map<String, Object?>>[];

  @override
  bool get supportsOverlaySurface => true;

  @override
  Future<void> create({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) async {
    created = true;
  }

  @override
  Future<void> setViewport({
    required double x,
    required double y,
    required double width,
    required double height,
    required double devicePixelRatio,
    required bool visible,
  }) async {
    viewports.add({
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'devicePixelRatio': devicePixelRatio,
      'visible': visible,
    });
  }
}

class DelayedViewportOverlayPapyrusPlatform extends OverlayPapyrusPlatform {
  Completer<void>? _firstViewportCompleter = Completer<void>();

  @override
  Future<void> setViewport({
    required double x,
    required double y,
    required double width,
    required double height,
    required double devicePixelRatio,
    required bool visible,
  }) async {
    await super.setViewport(
      x: x,
      y: y,
      width: width,
      height: height,
      devicePixelRatio: devicePixelRatio,
      visible: visible,
    );
    final completer = _firstViewportCompleter;
    if (completer != null) {
      await completer.future;
      _firstViewportCompleter = null;
    }
  }

  void completeViewportSync() {
    _firstViewportCompleter?.complete();
  }
}

class MethodSurfacePapyrusPlatform extends RecordingPapyrusPlatform {
  final createdConfigurations = <PapyrusConfiguration>[];

  @override
  Future<void> create({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) async {
    createdConfigurations.add(configuration);
  }
}

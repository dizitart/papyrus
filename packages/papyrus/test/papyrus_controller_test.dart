import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:papyrus/papyrus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    await tester.pump();

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
}

class RecordingPapyrusPlatform extends PapyrusPlatform {
  final loaded = <PapyrusLoadRequest>[];
  final commands = <String>[];

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

class MethodSurfacePapyrusPlatform extends RecordingPapyrusPlatform {
  final createdConfigurations = <PapyrusConfiguration>[];

  @override
  Future<void> create({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) async {
    createdConfigurations.add(configuration);
  }
}

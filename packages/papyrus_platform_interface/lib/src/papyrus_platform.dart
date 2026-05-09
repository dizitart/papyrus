import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models.dart';

abstract class PapyrusPlatform extends PlatformInterface {
  PapyrusPlatform() : super(token: _token);

  static final Object _token = Object();
  static PapyrusPlatform _instance = _UnsupportedPapyrusPlatform();

  // Setter kept explicit so platform registration can gain validation later.
  // ignore: unnecessary_getters_setters
  static PapyrusPlatform get instance => _instance;

  static set instance(PapyrusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<PapyrusEvent> get events => const Stream.empty();

  bool get supportsNativeView => false;

  bool get supportsOverlaySurface => false;

  String? get viewType => null;

  Future<void> create({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) async {}

  Future<void> setViewport({
    required double x,
    required double y,
    required double width,
    required double height,
    required double devicePixelRatio,
    required bool visible,
  }) async {}

  Future<void> load(PapyrusLoadRequest request) async {
    request.validate();
    throw const PapyrusException(
      PapyrusErrorCode.unsupportedPlatformFeature,
      'No Papyrus platform implementation is registered.',
    );
  }

  Future<void> reload() async {}

  Future<void> stopLoading() async {}

  Future<bool> canGoBack() async => false;

  Future<bool> canGoForward() async => false;

  Future<void> goBack() async {}

  Future<void> goForward() async {}

  Future<Uri?> currentUri() async => null;

  Future<String?> title() async => null;

  Future<double> estimatedProgress() async => 0;

  Future<Object?> evaluateJavaScript(String source) {
    throw const PapyrusException(
      PapyrusErrorCode.unsupportedPlatformFeature,
      'JavaScript evaluation is not supported by this platform.',
    );
  }

  Future<String?> selectedText() {
    throw const PapyrusException(
      PapyrusErrorCode.unsupportedPlatformFeature,
      'Selected-text queries are not supported by this platform.',
    );
  }

  Future<void> addJavaScriptChannel(String name) async {}

  Future<void> removeJavaScriptChannel(String name) async {}

  void setNavigationResolver(PapyrusNavigationResolver? resolver) {}

  void setResourceResolver(PapyrusResourceResolver? resolver) {}

  Future<PapyrusContentSize> getContentSize() {
    throw const PapyrusException(
      PapyrusErrorCode.unsupportedPlatformFeature,
      'Content-size querying is not supported by this platform.',
    );
  }

  Future<Uint8List> captureSnapshot({PapyrusSnapshotOptions? options}) {
    throw const PapyrusException(
      PapyrusErrorCode.unsupportedPlatformFeature,
      'Snapshot capture is not supported by this platform.',
    );
  }

  Future<void> printDocument({PapyrusPrintOptions? options}) {
    throw const PapyrusException(
      PapyrusErrorCode.unsupportedPlatformFeature,
      'Printing is not supported by this platform.',
    );
  }

  Future<void> clearCache() async {}

  Future<void> clearStorage(PapyrusStorageClearOptions options) async {}

  Future<void> dispose() async {}

  Future<PapyrusPlatformCapabilities> getCapabilities() async {
    return const PapyrusPlatformCapabilities(
      supportsResourceInterception: false,
      supportsVirtualSchemes: false,
      supportsEphemeralStorage: false,
      supportsPrint: false,
      supportsSnapshot: false,
      supportsAutoHeight: false,
      supportsDarkMode: false,
      supportsDownloadInterception: false,
      supportsPermissionInterception: false,
    );
  }
}

class _UnsupportedPapyrusPlatform extends PapyrusPlatform {}

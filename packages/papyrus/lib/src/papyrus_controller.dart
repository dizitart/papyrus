import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';

class PapyrusController {
  PapyrusController._(this._platform);

  final PapyrusPlatform _platform;

  static PapyrusController create() =>
      PapyrusController._(PapyrusPlatform.instance);

  Stream<PapyrusEvent> get events => _platform.events;

  Future<void> initialize({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) {
    return _platform.create(configuration: configuration);
  }

  Future<void> setViewport({
    required double x,
    required double y,
    required double width,
    required double height,
    required double devicePixelRatio,
    required bool visible,
  }) {
    return _platform.setViewport(
      x: x,
      y: y,
      width: width,
      height: height,
      devicePixelRatio: devicePixelRatio,
      visible: visible,
    );
  }

  Future<void> load(PapyrusLoadRequest request) => _platform.load(request);

  Future<void> loadHtmlString(
    String html, {
    Uri? baseUri,
    PapyrusContentMetadata? metadata,
  }) {
    return load(
      PapyrusHtmlRequest(html: html, baseUri: baseUri, metadata: metadata),
    );
  }

  Future<void> loadUri(Uri uri, {Map<String, String>? headers}) {
    return load(PapyrusUriRequest(uri: uri, headers: headers ?? const {}));
  }

  Future<void> loadFile(String absolutePath) {
    return load(PapyrusFileRequest(absolutePath: absolutePath));
  }

  Future<void> loadData(
    Uint8List bytes,
    String mimeType, {
    String? encoding,
    Uri? baseUri,
  }) {
    return load(
      PapyrusDataRequest(
        bytes: bytes,
        mimeType: mimeType,
        encoding: encoding,
        baseUri: baseUri,
      ),
    );
  }

  Future<void> reload() => _platform.reload();

  Future<void> stopLoading() => _platform.stopLoading();

  Future<bool> canGoBack() => _platform.canGoBack();

  Future<bool> canGoForward() => _platform.canGoForward();

  Future<void> goBack() => _platform.goBack();

  Future<void> goForward() => _platform.goForward();

  Future<Uri?> currentUri() => _platform.currentUri();

  Future<String?> title() => _platform.title();

  Future<double> estimatedProgress() => _platform.estimatedProgress();

  Future<Object?> evaluateJavaScript(String source) {
    return _platform.evaluateJavaScript(source);
  }

  Future<String?> selectedText() => _platform.selectedText();

  Future<void> copySelection() async {
    final text = await selectedText();
    if (text == null || text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<String?> quoteSelection({String prefix = '> '}) async {
    final text = await selectedText();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text.split('\n').map((line) => '$prefix$line').join('\n');
  }

  Future<void> addJavaScriptChannel(String name) {
    return _platform.addJavaScriptChannel(name);
  }

  Future<void> removeJavaScriptChannel(String name) {
    return _platform.removeJavaScriptChannel(name);
  }

  void setResourceResolver(PapyrusResourceResolver? resolver) {
    _platform.setResourceResolver(resolver);
  }

  Future<PapyrusContentSize> getContentSize() => _platform.getContentSize();

  Future<Uint8List> captureSnapshot({PapyrusSnapshotOptions? options}) {
    return _platform.captureSnapshot(options: options);
  }

  Future<void> printDocument({PapyrusPrintOptions? options}) {
    return _platform.printDocument(options: options);
  }

  Future<void> clearCache() => _platform.clearCache();

  Future<void> clearStorage(PapyrusStorageClearOptions options) {
    return _platform.clearStorage(options);
  }

  Future<PapyrusPlatformCapabilities> getCapabilities() {
    return _platform.getCapabilities();
  }

  Future<void> dispose() => _platform.dispose();
}

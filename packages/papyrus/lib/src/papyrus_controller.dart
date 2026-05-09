import 'package:flutter/services.dart';
import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';

/// Controls a Papyrus webview instance.
///
/// Create an instance with [create], initialize it via [initialize], then use
/// [load] and related methods to drive navigation and interaction.
class PapyrusController {
  PapyrusController._(this._platform);

  final PapyrusPlatform _platform;

  /// Creates a controller bound to the active [PapyrusPlatform.instance].
  static PapyrusController create() =>
      PapyrusController._(PapyrusPlatform.instance);

  /// A stream of page lifecycle, progress, error, and content-size events.
  Stream<PapyrusEvent> get events => _platform.events;

  /// Initializes the underlying platform webview with [configuration].
  Future<void> initialize({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) {
    return _platform.create(configuration: configuration);
  }

  /// Updates viewport geometry for overlay-based desktop webview surfaces.
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

  /// Loads a generic [PapyrusLoadRequest].
  Future<void> load(PapyrusLoadRequest request) => _platform.load(request);

  /// Loads inline [html] content.
  Future<void> loadHtmlString(
    String html, {
    Uri? baseUri,
    PapyrusContentMetadata? metadata,
  }) {
    return load(
      PapyrusHtmlRequest(html: html, baseUri: baseUri, metadata: metadata),
    );
  }

  /// Navigates to [uri] with optional HTTP [headers].
  Future<void> loadUri(Uri uri, {Map<String, String>? headers}) {
    return load(PapyrusUriRequest(uri: uri, headers: headers ?? const {}));
  }

  /// Loads a local file from [absolutePath].
  Future<void> loadFile(String absolutePath) {
    return load(PapyrusFileRequest(absolutePath: absolutePath));
  }

  /// Loads raw [bytes] with a [mimeType].
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

  /// Reloads the current page.
  Future<void> reload() => _platform.reload();

  /// Stops the in-flight page load.
  Future<void> stopLoading() => _platform.stopLoading();

  /// Returns whether backward navigation is available.
  Future<bool> canGoBack() => _platform.canGoBack();

  /// Returns whether forward navigation is available.
  Future<bool> canGoForward() => _platform.canGoForward();

  /// Navigates backward in history if possible.
  Future<void> goBack() => _platform.goBack();

  /// Navigates forward in history if possible.
  Future<void> goForward() => _platform.goForward();

  /// Returns the current page URI, if known.
  Future<Uri?> currentUri() => _platform.currentUri();

  /// Returns the current document title, if available.
  Future<String?> title() => _platform.title();

  /// Returns an estimated loading progress value in the range `0.0..1.0`.
  Future<double> estimatedProgress() => _platform.estimatedProgress();

  /// Evaluates JavaScript [source] in the page context.
  Future<Object?> evaluateJavaScript(String source) {
    return _platform.evaluateJavaScript(source);
  }

  /// Returns currently selected text in the page, if any.
  Future<String?> selectedText() => _platform.selectedText();

  /// Copies the selected text to the system clipboard.
  Future<void> copySelection() async {
    final text = await selectedText();
    if (text == null || text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Returns the selected text formatted as quoted lines.
  Future<String?> quoteSelection({String prefix = '> '}) async {
    final text = await selectedText();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text.split('\n').map((line) => '$prefix$line').join('\n');
  }

  /// Registers a JavaScript channel [name] for page-to-host messaging.
  Future<void> addJavaScriptChannel(String name) {
    return _platform.addJavaScriptChannel(name);
  }

  /// Removes a previously registered JavaScript channel [name].
  Future<void> removeJavaScriptChannel(String name) {
    return _platform.removeJavaScriptChannel(name);
  }

  /// Sets a navigation decision callback.
  void setNavigationResolver(PapyrusNavigationResolver? resolver) {
    _platform.setNavigationResolver(resolver);
  }

  /// Sets a resource interception callback.
  void setResourceResolver(PapyrusResourceResolver? resolver) {
    _platform.setResourceResolver(resolver);
  }

  /// Returns the measured page content size.
  Future<PapyrusContentSize> getContentSize() => _platform.getContentSize();

  /// Captures a bitmap snapshot of the current page.
  Future<Uint8List> captureSnapshot({PapyrusSnapshotOptions? options}) {
    return _platform.captureSnapshot(options: options);
  }

  /// Invokes native print support for the current document.
  Future<void> printDocument({PapyrusPrintOptions? options}) {
    return _platform.printDocument(options: options);
  }

  /// Clears the platform webview cache.
  Future<void> clearCache() => _platform.clearCache();

  /// Clears storage according to [options].
  Future<void> clearStorage(PapyrusStorageClearOptions options) {
    return _platform.clearStorage(options);
  }

  /// Returns the capabilities exposed by the active platform implementation.
  Future<PapyrusPlatformCapabilities> getCapabilities() {
    return _platform.getCapabilities();
  }

  /// Releases native resources owned by this controller.
  Future<void> dispose() => _platform.dispose();
}

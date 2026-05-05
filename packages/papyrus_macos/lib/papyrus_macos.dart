import 'package:flutter/services.dart';
import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';

class PapyrusMacos extends PapyrusPlatform {
  PapyrusMacos({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.papyrus.papyrus_macos');

  final MethodChannel _channel;

  static void registerWith() {
    PapyrusPlatform.instance = PapyrusMacos();
  }

  @override
  Future<void> create({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) => _channel.invokeMethod<void>('create', _configurationMap(configuration));

  @override
  Future<void> load(PapyrusLoadRequest request) {
    request.validate();
    return _channel.invokeMethod<void>('load', request.toMap());
  }

  @override
  Future<void> reload() => _channel.invokeMethod<void>('reload');

  @override
  Future<void> stopLoading() => _channel.invokeMethod<void>('stopLoading');

  @override
  Future<bool> canGoBack() async =>
      await _channel.invokeMethod<bool>('canGoBack') ?? false;

  @override
  Future<bool> canGoForward() async =>
      await _channel.invokeMethod<bool>('canGoForward') ?? false;

  @override
  Future<void> goBack() => _channel.invokeMethod<void>('goBack');

  @override
  Future<void> goForward() => _channel.invokeMethod<void>('goForward');

  @override
  Future<Uri?> currentUri() async {
    final value = await _channel.invokeMethod<String>('currentUri');
    return value == null ? null : Uri.tryParse(value);
  }

  @override
  Future<String?> title() => _channel.invokeMethod<String>('title');

  @override
  Future<double> estimatedProgress() async =>
      await _channel.invokeMethod<double>('estimatedProgress') ?? 0;

  @override
  Future<Object?> evaluateJavaScript(String source) =>
      _channel.invokeMethod<Object?>('evaluateJavaScript', source);

  @override
  Future<PapyrusContentSize> getContentSize() async {
    final map = await _channel.invokeMapMethod<String, Object?>(
      'getContentSize',
    );
    return PapyrusContentSize(
      width: (map?['width'] as num? ?? 0).toDouble(),
      height: (map?['height'] as num? ?? 0).toDouble(),
    );
  }

  @override
  Future<Uint8List> captureSnapshot({PapyrusSnapshotOptions? options}) async {
    final bytes = await _channel.invokeMethod<Uint8List>('captureSnapshot');
    return bytes ?? Uint8List(0);
  }

  @override
  Future<void> printDocument({PapyrusPrintOptions? options}) => _channel
      .invokeMethod<void>('printDocument', {'jobName': options?.jobName});

  @override
  Future<void> clearCache() => _channel.invokeMethod<void>('clearCache');

  @override
  Future<void> clearStorage(PapyrusStorageClearOptions options) =>
      _channel.invokeMethod<void>('clearStorage');

  @override
  Future<void> dispose() => _channel.invokeMethod<void>('dispose');

  @override
  Future<PapyrusPlatformCapabilities> getCapabilities() async {
    final map = await _channel.invokeMapMethod<String, Object?>(
      'getCapabilities',
    );
    return _capabilitiesFromMap(map) ??
        const PapyrusPlatformCapabilities(
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

Map<String, Object?> _configurationMap(PapyrusConfiguration configuration) => {
  'allowJavaScript':
      configuration.security.allowJavaScript ||
      configuration.javascript.mode != PapyrusJavaScriptMode.disabled,
  'ephemeral': configuration.storage.ephemeral,
  'autoHeight': configuration.display.autoHeight,
  'zoomEnabled': configuration.display.zoomEnabled,
};

PapyrusPlatformCapabilities? _capabilitiesFromMap(Map<String, Object?>? map) {
  if (map == null) return null;
  return PapyrusPlatformCapabilities(
    supportsResourceInterception: map['supportsResourceInterception'] == true,
    supportsVirtualSchemes: map['supportsVirtualSchemes'] == true,
    supportsEphemeralStorage: map['supportsEphemeralStorage'] == true,
    supportsPrint: map['supportsPrint'] == true,
    supportsSnapshot: map['supportsSnapshot'] == true,
    supportsAutoHeight: map['supportsAutoHeight'] == true,
    supportsDarkMode: map['supportsDarkMode'] == true,
    supportsDownloadInterception: map['supportsDownloadInterception'] == true,
    supportsPermissionInterception:
        map['supportsPermissionInterception'] == true,
  );
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';

class PapyrusWindows extends PapyrusPlatform {
  PapyrusWindows({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.papyrus.papyrus_windows');

  final MethodChannel _channel;
  final StreamController<PapyrusEvent> _events =
      StreamController<PapyrusEvent>.broadcast();
  PapyrusResourceResolver? _resourceResolver;
  bool _methodHandlerInstalled = false;

  static void registerWith() {
    PapyrusPlatform.instance = PapyrusWindows();
  }

  @override
  Stream<PapyrusEvent> get events {
    _ensureMethodHandlerInstalled();
    return _events.stream;
  }

  @override
  bool get supportsOverlaySurface => true;

  @override
  void setResourceResolver(PapyrusResourceResolver? resolver) {
    _ensureMethodHandlerInstalled();
    _resourceResolver = resolver;
    unawaited(
      _channel.invokeMethod<void>(
        'setResourceResolverEnabled',
        resolver != null,
      ),
    );
  }

  @override
  Future<void> create({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) {
    final config = _configurationMap(configuration);
    config['resourceResolverEnabled'] = _resourceResolver != null;
    return _channel.invokeMethod<void>('create', config);
  }

  @override
  Future<void> setViewport({
    required double x,
    required double y,
    required double width,
    required double height,
    required double devicePixelRatio,
    required bool visible,
  }) {
    return _channel.invokeMethod<void>('setViewport', {
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'devicePixelRatio': devicePixelRatio,
      'visible': visible,
    });
  }

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
  Future<double> estimatedProgress() async {
    final value = await _channel.invokeMethod<num>('estimatedProgress');
    return value?.toDouble() ?? 0;
  }

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
  Future<void> printDocument({PapyrusPrintOptions? options}) =>
      _channel.invokeMethod<void>('printDocument');

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
          supportsEphemeralStorage: false,
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
  'allowFileAccess': configuration.security.allowFileAccess,
  'allowPopups': configuration.security.allowPopups,
  'allowMixedContent': configuration.security.allowMixedContent,
  'ephemeral': configuration.storage.ephemeral,
  'autoHeight': configuration.display.autoHeight,
  'zoomEnabled': configuration.display.zoomEnabled,
  'virtualResourceScheme':
      configuration.resources.virtualResourceOrigin?.scheme ??
      'papyrus-resource',
  'remoteResources': configuration.resources.remoteResources.name,
  'allowedHosts': configuration.resources.allowedHosts.toList(),
  'allowedSchemes': configuration.resources.allowedSchemes.toList(),
  'blockedResourceTypes': configuration.resources.blockedResourceTypes
      .map((type) => type.name)
      .toList(),
  'enableRequestInterception':
      configuration.resources.enableRequestInterception,
  'debuggingEnabled': configuration.platform.debuggingEnabled,
  'hardwareAcceleration': configuration.platform.hardwareAcceleration.name,
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

extension on PapyrusWindows {
  void _ensureMethodHandlerInstalled() {
    if (_methodHandlerInstalled) {
      return;
    }
    _channel.setMethodCallHandler(_handleMethodCall);
    _methodHandlerInstalled = true;
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'pageStarted':
        _events.add(
          PapyrusPageStartedEvent(uri: _tryParseUri(call.arguments as String?)),
        );
        return null;
      case 'pageFinished':
        _events.add(
          PapyrusPageFinishedEvent(
            uri: _tryParseUri(call.arguments as String?),
          ),
        );
        return null;
      case 'progress':
        _events.add(
          PapyrusProgressEvent((call.arguments as num?)?.toDouble() ?? 0),
        );
        return null;
      case 'resourceRequest':
        final request = PapyrusResourceRequest.fromMap(
          _mapArguments(call.arguments),
        );
        final resolver = _resourceResolver;
        final decision = resolver == null
            ? const PapyrusAllowResource()
            : await resolver(request);
        return papyrusResourceDecisionToMap(decision);
      default:
        return null;
    }
  }
}

Map<Object?, Object?> _mapArguments(Object? arguments) {
  if (arguments is Map<Object?, Object?>) {
    return arguments;
  }
  return const {};
}

Uri? _tryParseUri(String? value) => value == null ? null : Uri.tryParse(value);

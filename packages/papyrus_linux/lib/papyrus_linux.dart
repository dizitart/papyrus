import 'dart:async';

import 'package:flutter/services.dart';
import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';

class PapyrusLinux extends PapyrusPlatform {
  PapyrusLinux({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.papyrus.papyrus_linux');

  final MethodChannel _channel;
  final StreamController<PapyrusEvent> _events =
      StreamController<PapyrusEvent>.broadcast();
  PapyrusNavigationResolver? _navigationResolver;
  PapyrusResourceResolver? _resourceResolver;
  bool _methodHandlerInstalled = false;

  static void registerWith() {
    PapyrusPlatform.instance = PapyrusLinux();
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
      _invokeMethod<void>(
        'setResourceResolverEnabled',
        resolver != null,
      ),
    );
  }

  @override
  void setNavigationResolver(PapyrusNavigationResolver? resolver) {
    _ensureMethodHandlerInstalled();
    _navigationResolver = resolver;
    unawaited(
      _invokeMethod<void>(
        'setNavigationResolverEnabled',
        resolver != null,
      ),
    );
  }

  @override
  Future<void> create({
    PapyrusConfiguration configuration = const PapyrusConfiguration(),
  }) {
    final config = _configurationMap(configuration);
    config['navigationResolverEnabled'] = _navigationResolver != null;
    config['resourceResolverEnabled'] = _resourceResolver != null;
    return _invokeMethod<void>('create', config);
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
    return _invokeMethod<void>('setViewport', {
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
    return _invokeMethod<void>('load', request.toMap());
  }

  @override
  Future<void> reload() => _invokeMethod<void>('reload');

  @override
  Future<void> stopLoading() => _invokeMethod<void>('stopLoading');

  @override
  Future<bool> canGoBack() async =>
      await _invokeMethod<bool>('canGoBack') ?? false;

  @override
  Future<bool> canGoForward() async =>
      await _invokeMethod<bool>('canGoForward') ?? false;

  @override
  Future<void> goBack() => _invokeMethod<void>('goBack');

  @override
  Future<void> goForward() => _invokeMethod<void>('goForward');

  @override
  Future<Uri?> currentUri() async {
    final value = await _invokeMethod<String>('currentUri');
    return value == null ? null : Uri.tryParse(value);
  }

  @override
  Future<String?> title() => _invokeMethod<String>('title');

  @override
  Future<double> estimatedProgress() async {
    final value = await _invokeMethod<num>('estimatedProgress');
    return value?.toDouble() ?? 0;
  }

  @override
  Future<Object?> evaluateJavaScript(String source) =>
      _invokeMethod<Object?>('evaluateJavaScript', source);

  @override
  Future<String?> selectedText() async {
    final value = await _invokeMethod<String>('selectedText');
    if (value == null || value.isEmpty) {
      return null;
    }
    return Uri.decodeComponent(value);
  }

  @override
  Future<PapyrusContentSize> getContentSize() async {
    final map = await _invokeMapMethod(
      'getContentSize',
    );
    return PapyrusContentSize(
      width: (map?['width'] as num? ?? 0).toDouble(),
      height: (map?['height'] as num? ?? 0).toDouble(),
    );
  }

  @override
  Future<Uint8List> captureSnapshot({PapyrusSnapshotOptions? options}) async {
    final bytes = await _invokeMethod<Uint8List>('captureSnapshot');
    return bytes ?? Uint8List(0);
  }

  @override
  Future<void> printDocument({PapyrusPrintOptions? options}) =>
      _invokeMethod<void>('printDocument');

  @override
  Future<void> clearCache() => _invokeMethod<void>('clearCache');

  @override
  Future<void> clearStorage(PapyrusStorageClearOptions options) =>
      _invokeMethod<void>('clearStorage');

  @override
  Future<void> dispose() => _invokeMethod<void>('dispose');

  @override
  Future<PapyrusPlatformCapabilities> getCapabilities() async {
    final map = await _invokeMapMethod(
      'getCapabilities',
    );
    return _capabilitiesFromMap(map) ??
        const PapyrusPlatformCapabilities(
          supportsResourceInterception: true,
          supportsVirtualSchemes: true,
          supportsEphemeralStorage: true,
          supportsPrint: false,
          supportsSnapshot: true,
          supportsAutoHeight: true,
          supportsDarkMode: true,
          supportsDownloadInterception: true,
          supportsPermissionInterception: true,
        );
  }
}

Map<String, Object?> _configurationMap(PapyrusConfiguration configuration) =>
    papyrusConfigurationToMap(configuration);

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

extension on PapyrusLinux {
  Future<T?> _invokeMethod<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw _papyrusExceptionFromPlatformError(error);
    }
  }

  Future<Map<String, Object?>?> _invokeMapMethod(String method) async {
    try {
      return await _channel.invokeMapMethod<String, Object?>(method);
    } on PlatformException catch (error) {
      throw _papyrusExceptionFromPlatformError(error);
    }
  }

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
      case 'navigationRequest':
        final resolver = _navigationResolver;
        if (resolver == null) {
          return null;
        }
        final decision = await resolver(
          _navigationRequestFromArguments(call.arguments),
        );
        return papyrusNavigationDecisionToMap(decision);
      default:
        return null;
    }
  }
}

PapyrusException _papyrusExceptionFromPlatformError(PlatformException error) {
  final code = switch (error.code) {
    'navigationBlocked' => PapyrusErrorCode.navigationBlocked,
    'resourceBlocked' => PapyrusErrorCode.resourceBlocked,
    'networkFailed' => PapyrusErrorCode.networkFailed,
    'sslFailed' => PapyrusErrorCode.sslFailed,
    'timeout' => PapyrusErrorCode.timeout,
    'rendererCrashed' => PapyrusErrorCode.rendererCrashed,
    'unsupportedPlatformFeature' =>
      PapyrusErrorCode.unsupportedPlatformFeature,
    'invalidLoadRequest' => PapyrusErrorCode.invalidLoadRequest,
    'webViewUnavailable' => PapyrusErrorCode.webViewUnavailable,
    _ => PapyrusErrorCode.unknown,
  };

  final details = error.details;
  final uri = switch (details) {
    String value => Uri.tryParse(value),
    Map<Object?, Object?> value when value['uri'] is String =>
      Uri.tryParse(value['uri'] as String),
    _ => null,
  };

  return PapyrusException(code, error.message ?? error.code, uri: uri);
}

Map<Object?, Object?> _mapArguments(Object? arguments) {
  if (arguments is Map<Object?, Object?>) {
    return arguments;
  }
  return const {};
}

PapyrusNavigationRequest _navigationRequestFromArguments(Object? arguments) {
  if (arguments is Map<Object?, Object?>) {
    return PapyrusNavigationRequest.fromMap(arguments);
  }
  return PapyrusNavigationRequest(
    uri: Uri.parse(arguments as String? ?? ''),
    isMainFrame: true,
    navigationType: PapyrusNavigationType.other,
    hasUserGesture: false,
  );
}

Uri? _tryParseUri(String? value) => value == null ? null : Uri.tryParse(value);

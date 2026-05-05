import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';

import 'papyrus_controller.dart';

class PapyrusView extends StatefulWidget {
  const PapyrusView({
    super.key,
    required this.controller,
    this.initialRequest,
    this.configuration = const PapyrusConfiguration(),
    this.gestureRecognizers,
    this.onCreated,
    this.onPageStarted,
    this.onPageFinished,
    this.onProgressChanged,
    this.onNavigationRequest,
    this.onResourceRequest,
    this.onDownloadRequest,
    this.onPermissionRequest,
    this.onConsoleMessage,
    this.onWebMessage,
    this.onError,
    this.onContentSizeChanged,
  });

  final PapyrusController controller;
  final PapyrusLoadRequest? initialRequest;
  final PapyrusConfiguration configuration;
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;
  final ValueChanged<PapyrusController>? onCreated;
  final ValueChanged<PapyrusPageStartedEvent>? onPageStarted;
  final ValueChanged<PapyrusPageFinishedEvent>? onPageFinished;
  final ValueChanged<PapyrusProgressEvent>? onProgressChanged;
  final Future<PapyrusNavigationDecision> Function(PapyrusNavigationRequest)?
  onNavigationRequest;
  final Future<PapyrusResourceDecision> Function(PapyrusResourceRequest)?
  onResourceRequest;
  final Future<PapyrusDownloadDecision> Function(PapyrusDownloadRequest)?
  onDownloadRequest;
  final Future<PapyrusPermissionDecision> Function(PapyrusPermissionRequest)?
  onPermissionRequest;
  final ValueChanged<PapyrusConsoleMessage>? onConsoleMessage;
  final ValueChanged<PapyrusWebMessage>? onWebMessage;
  final ValueChanged<PapyrusErrorEvent>? onError;
  final ValueChanged<PapyrusContentSize>? onContentSizeChanged;

  @override
  State<PapyrusView> createState() => _PapyrusViewState();
}

class _PapyrusViewState extends State<PapyrusView> {
  StreamSubscription<PapyrusEvent>? _subscription;
  bool _nativeViewCreated = false;
  bool _initialLoadStarted = false;
  bool _overlayViewportReady = false;

  @override
  void initState() {
    super.initState();
    widget.onCreated?.call(widget.controller);
    _subscription = widget.controller.events.listen(_handleEvent);
    if (_usesMethodChannelSurface) {
      _initializeMethodChannelSurface();
    }
  }

  @override
  void didUpdateWidget(PapyrusView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    final configurationChanged =
        _configurationSignature(oldWidget.configuration) !=
        _configurationSignature(widget.configuration);
    final initialRequestChanged =
        _requestSignature(oldWidget.initialRequest) !=
        _requestSignature(widget.initialRequest);

    if (controllerChanged) {
      unawaited(_subscription?.cancel());
      _subscription = widget.controller.events.listen(_handleEvent);
      widget.onCreated?.call(widget.controller);
    }

    if (controllerChanged || configurationChanged || initialRequestChanged) {
      _initialLoadStarted = false;
    }

    if (controllerChanged) {
      _nativeViewCreated = false;
      _overlayViewportReady = false;
      if (_usesMethodChannelSurface) {
        _initializeMethodChannelSurface();
      }
      return;
    }

    if (_usesMethodChannelSurface) {
      if (configurationChanged) {
        _initializeMethodChannelSurface();
      } else if (initialRequestChanged) {
        _loadInitialRequest();
      }
      return;
    }

    if (configurationChanged) {
      _nativeViewCreated = false;
      return;
    }

    if (initialRequestChanged) {
      _loadInitialRequest();
    }
  }

  void _handleEvent(PapyrusEvent event) {
    switch (event) {
      case PapyrusPageStartedEvent():
        widget.onPageStarted?.call(event);
      case PapyrusPageFinishedEvent():
        widget.onPageFinished?.call(event);
      case PapyrusProgressEvent():
        widget.onProgressChanged?.call(event);
      case PapyrusErrorEvent():
        widget.onError?.call(event);
      case PapyrusContentSizeChangedEvent():
        widget.onContentSizeChanged?.call(event.size);
      default:
        break;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (PapyrusPlatform.instance.supportsOverlaySurface) {
      unawaited(
        widget.controller.setViewport(
          x: 0,
          y: 0,
          width: 0,
          height: 0,
          devicePixelRatio: 1,
          visible: false,
        ),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = PapyrusPlatform.instance;
    if (platform.supportsOverlaySurface) {
      return _DesktopOverlaySurface(
        controller: widget.controller,
        onViewportReady: _handleOverlayViewportReady,
      );
    }

    final viewType = platform.viewType;
    if (!platform.supportsNativeView || viewType == null) {
      return const _UnsupportedNativeView();
    }

    final creationParams = _configurationMap(widget.configuration);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          key: ValueKey<String>(_configurationSignature(widget.configuration)),
          viewType: viewType,
          onPlatformViewCreated: _handlePlatformViewCreated,
          gestureRecognizers: widget.gestureRecognizers,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.iOS:
        return UiKitView(
          key: ValueKey<String>(_configurationSignature(widget.configuration)),
          viewType: viewType,
          onPlatformViewCreated: _handlePlatformViewCreated,
          gestureRecognizers: widget.gestureRecognizers,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.macOS:
        return AppKitView(
          key: ValueKey<String>(_configurationSignature(widget.configuration)),
          viewType: viewType,
          onPlatformViewCreated: _handlePlatformViewCreated,
          gestureRecognizers: widget.gestureRecognizers,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return const _UnsupportedNativeView();
    }
  }

  void _handlePlatformViewCreated(int id) {
    if (!mounted) return;
    _nativeViewCreated = true;
    _loadInitialRequest();
  }

  void _initializeMethodChannelSurface() {
    _nativeViewCreated = false;
    final controller = widget.controller;
    unawaited(
      controller.initialize(configuration: widget.configuration).then((_) {
        if (!mounted || widget.controller != controller) return;
        _nativeViewCreated = true;
        _loadInitialRequest();
      }),
    );
  }

  void _loadInitialRequest() {
    if (!_nativeViewCreated || _initialLoadStarted) return;
    if (PapyrusPlatform.instance.supportsOverlaySurface &&
        !_overlayViewportReady) {
      return;
    }
    final request = widget.initialRequest;
    if (request == null) return;
    _initialLoadStarted = true;
    unawaited(widget.controller.load(request));
  }

  void _handleOverlayViewportReady() {
    if (_overlayViewportReady) return;
    _overlayViewportReady = true;
    _loadInitialRequest();
  }

  bool get _usesMethodChannelSurface {
    final platform = PapyrusPlatform.instance;
    return !platform.supportsNativeView || platform.supportsOverlaySurface;
  }
}

class _DesktopOverlaySurface extends StatefulWidget {
  const _DesktopOverlaySurface({
    required this.controller,
    required this.onViewportReady,
  });

  final PapyrusController controller;
  final VoidCallback onViewportReady;

  @override
  State<_DesktopOverlaySurface> createState() => _DesktopOverlaySurfaceState();
}

class _DesktopOverlaySurfaceState extends State<_DesktopOverlaySurface>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final GlobalKey _key = GlobalKey();
  late final Ticker _ticker;
  _ViewportSnapshot? _lastSent;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((_) => _scheduleViewportSync())..start();
    _scheduleViewportSync();
  }

  @override
  void didUpdateWidget(_DesktopOverlaySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _lastSent = null;
    _scheduleViewportSync();
  }

  @override
  void didChangeMetrics() {
    _lastSent = null;
    _scheduleViewportSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    unawaited(
      widget.controller.setViewport(
        x: 0,
        y: 0,
        width: 0,
        height: 0,
        devicePixelRatio: 1,
        visible: false,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleViewportSync();
    return MouseRegion(
      opaque: false,
      child: SizedBox.expand(
        key: _key,
        child: const ColoredBox(color: Colors.transparent),
      ),
    );
  }

  void _scheduleViewportSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _syncViewport());
  }

  void _syncViewport() {
    _syncScheduled = false;
    if (!mounted) return;
    final context = _key.currentContext;
    if (context == null) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;

    final offset = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;
    final devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final visible = size.width > 0 && size.height > 0;
    final snapshot = _ViewportSnapshot(
      x: _snapToPhysicalPixel(offset.dx, devicePixelRatio),
      y: _snapToPhysicalPixel(offset.dy, devicePixelRatio),
      width: _snapToPhysicalPixel(size.width, devicePixelRatio),
      height: _snapToPhysicalPixel(size.height, devicePixelRatio),
      devicePixelRatio: devicePixelRatio,
      visible: visible,
    );
    if (snapshot == _lastSent) return;
    _lastSent = snapshot;
    unawaited(
      widget.controller.setViewport(
        x: snapshot.x,
        y: snapshot.y,
        width: snapshot.width,
        height: snapshot.height,
        devicePixelRatio: snapshot.devicePixelRatio,
        visible: snapshot.visible,
      ),
    );
    if (snapshot.visible && snapshot.width > 0 && snapshot.height > 0) {
      widget.onViewportReady();
    }
  }
}

double _snapToPhysicalPixel(double value, double devicePixelRatio) {
  return (value * devicePixelRatio).roundToDouble() / devicePixelRatio;
}

@immutable
class _ViewportSnapshot {
  const _ViewportSnapshot({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.devicePixelRatio,
    required this.visible,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final double devicePixelRatio;
  final bool visible;

  @override
  bool operator ==(Object other) {
    return other is _ViewportSnapshot &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height &&
        other.devicePixelRatio == devicePixelRatio &&
        other.visible == visible;
  }

  @override
  int get hashCode =>
      Object.hash(x, y, width, height, devicePixelRatio, visible);
}

class _UnsupportedNativeView extends StatelessWidget {
  const _UnsupportedNativeView();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFFAFAFA),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Papyrus native WebView embedding is not available on this Flutter platform.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
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
  'textZoom': configuration.display.textZoom,
  'debuggingEnabled': configuration.platform.debuggingEnabled,
  'hardwareAcceleration': configuration.platform.hardwareAcceleration.name,
};

String _configurationSignature(PapyrusConfiguration configuration) =>
    _configurationMap(configuration).toString();

String? _requestSignature(PapyrusLoadRequest? request) =>
    request?.toMap().toString();

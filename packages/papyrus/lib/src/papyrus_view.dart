import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  void initState() {
    super.initState();
    widget.onCreated?.call(widget.controller);
    _subscription = widget.controller.events.listen(_handleEvent);
    if (!PapyrusPlatform.instance.supportsNativeView) {
      _nativeViewCreated = true;
      unawaited(
        widget.controller.initialize(configuration: widget.configuration),
      );
      _loadInitialRequest();
    }
  }

  @override
  void didUpdateWidget(PapyrusView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      unawaited(_subscription?.cancel());
      _subscription = widget.controller.events.listen(_handleEvent);
      widget.onCreated?.call(widget.controller);
      _initialLoadStarted = false;
      _nativeViewCreated = !PapyrusPlatform.instance.supportsNativeView;
      if (_nativeViewCreated) {
        unawaited(
          widget.controller.initialize(configuration: widget.configuration),
        );
        _loadInitialRequest();
      }
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = PapyrusPlatform.instance;
    final viewType = platform.viewType;
    if (!platform.supportsNativeView || viewType == null) {
      return const _UnsupportedNativeView();
    }

    final creationParams = _configurationMap(widget.configuration);
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: viewType,
          onPlatformViewCreated: _handlePlatformViewCreated,
          gestureRecognizers: widget.gestureRecognizers,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.iOS:
        return UiKitView(
          viewType: viewType,
          onPlatformViewCreated: _handlePlatformViewCreated,
          gestureRecognizers: widget.gestureRecognizers,
          creationParams: creationParams,
          creationParamsCodec: const StandardMessageCodec(),
        );
      case TargetPlatform.macOS:
        return AppKitView(
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

  void _loadInitialRequest() {
    if (!_nativeViewCreated || _initialLoadStarted) return;
    final request = widget.initialRequest;
    if (request == null) return;
    _initialLoadStarted = true;
    unawaited(widget.controller.load(request));
  }
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
};

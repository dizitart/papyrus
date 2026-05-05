import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
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

  @override
  void initState() {
    super.initState();
    widget.onCreated?.call(widget.controller);
    _subscription = widget.controller.events.listen(_handleEvent);
    final request = widget.initialRequest;
    if (request != null) {
      unawaited(widget.controller.load(request));
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
    return const SizedBox.shrink();
  }
}

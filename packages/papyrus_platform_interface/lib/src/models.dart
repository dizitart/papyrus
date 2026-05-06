import 'dart:typed_data';

typedef JsonMap = Map<String, Object?>;

enum PapyrusNavigationType {
  linkClicked,
  formSubmitted,
  backForward,
  reload,
  programmatic,
  other,
}

enum PapyrusNavigationDecision { allow, block, openExternally, download }

enum PapyrusResourceType {
  document,
  stylesheet,
  image,
  font,
  script,
  xhr,
  media,
  iframe,
  other,
}

enum PapyrusRemoteResourceMode { block, allowAll, allowByHost, askHostApp }

enum PapyrusJavaScriptMode { disabled, restricted, unrestricted }

enum PapyrusCookiePolicy { block, allow, allowByHost }

enum PapyrusStorageMode { disabled, enabled }

enum PapyrusCacheMode { defaultMode, noCache, cacheOnly }

enum PapyrusPermissionType {
  camera,
  microphone,
  geolocation,
  notifications,
  clipboardRead,
  clipboardWrite,
  protectedMedia,
  fileChooser,
}

enum PapyrusPermissionDecision { grant, deny, promptHostApp }

enum PapyrusDownloadDecision { block, allowSystemDownload, handToHostApp }

enum PapyrusErrorCode {
  unknown,
  navigationBlocked,
  resourceBlocked,
  networkFailed,
  sslFailed,
  timeout,
  rendererCrashed,
  unsupportedPlatformFeature,
  invalidLoadRequest,
  webViewUnavailable,
}

enum PapyrusDarkMode { system, light, dark }

enum PapyrusHardwareAccelerationMode { auto, hardware, software }

class PapyrusException implements Exception {
  const PapyrusException(this.code, this.message, {this.uri});

  final PapyrusErrorCode code;
  final String message;
  final Uri? uri;

  @override
  String toString() => 'PapyrusException(${code.name}, $message)';
}

sealed class PapyrusLoadRequest {
  const PapyrusLoadRequest();

  String get type;

  JsonMap toMap();

  void validate();
}

class PapyrusHtmlRequest extends PapyrusLoadRequest {
  const PapyrusHtmlRequest({
    required this.html,
    this.baseUri,
    this.metadata,
    this.virtualResources = const [],
  });

  final String html;
  final Uri? baseUri;
  final PapyrusContentMetadata? metadata;
  final List<PapyrusVirtualResource> virtualResources;

  @override
  String get type => 'html';

  @override
  JsonMap toMap() => {
    'type': type,
    'html': PapyrusHtmlComposer.ensureDocument(html),
    'baseUri': baseUri?.toString(),
    'metadata': metadata?.toMap(),
    'virtualResources': virtualResources
        .map((resource) => resource.toMap())
        .toList(),
  };

  @override
  void validate() {
    if (html.isEmpty) {
      throw ArgumentError.value(html, 'html', 'HTML must not be empty.');
    }
  }

  PapyrusHtmlRequest withContentSecurityPolicy(String? contentSecurityPolicy) {
    if (contentSecurityPolicy == null || contentSecurityPolicy.isEmpty) {
      return this;
    }
    return PapyrusHtmlRequest(
      html: PapyrusHtmlComposer.injectContentSecurityPolicy(
        html,
        contentSecurityPolicy,
      ),
      baseUri: baseUri,
      metadata: metadata,
      virtualResources: virtualResources,
    );
  }
}

class PapyrusUriRequest extends PapyrusLoadRequest {
  const PapyrusUriRequest({required this.uri, this.headers = const {}});

  final Uri uri;
  final Map<String, String> headers;

  @override
  String get type => 'uri';

  @override
  JsonMap toMap() => {'type': type, 'uri': uri.toString(), 'headers': headers};

  @override
  void validate() {
    if (!uri.hasScheme) {
      throw ArgumentError.value(uri, 'uri', 'URI must be absolute.');
    }
  }
}

class PapyrusFileRequest extends PapyrusLoadRequest {
  const PapyrusFileRequest({required this.absolutePath});

  final String absolutePath;

  @override
  String get type => 'file';

  @override
  JsonMap toMap() => {'type': type, 'absolutePath': absolutePath};

  @override
  void validate() {
    if (!absolutePath.startsWith('/')) {
      throw ArgumentError.value(
        absolutePath,
        'absolutePath',
        'File requests require an absolute path.',
      );
    }
  }
}

class PapyrusDataRequest extends PapyrusLoadRequest {
  const PapyrusDataRequest({
    required this.bytes,
    required this.mimeType,
    this.encoding,
    this.baseUri,
  });

  final Uint8List bytes;
  final String mimeType;
  final String? encoding;
  final Uri? baseUri;

  @override
  String get type => 'data';

  @override
  JsonMap toMap() => {
    'type': type,
    'bytes': bytes.toList(),
    'mimeType': mimeType,
    'encoding': encoding,
    'baseUri': baseUri?.toString(),
  };

  @override
  void validate() {
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'Data must not be empty.');
    }
    if (mimeType.isEmpty || !mimeType.contains('/')) {
      throw ArgumentError.value(mimeType, 'mimeType', 'Invalid MIME type.');
    }
  }
}

class PapyrusContentMetadata {
  const PapyrusContentMetadata({
    this.contentType,
    this.source,
    this.identifier,
    this.extra = const {},
  });

  final String? contentType;
  final String? source;
  final String? identifier;
  final Map<String, String> extra;

  JsonMap toMap() => {
    'contentType': contentType,
    'source': source,
    'identifier': identifier,
    'extra': extra,
  };
}

class PapyrusConfiguration {
  const PapyrusConfiguration({
    this.security = const PapyrusSecurityPolicy(),
    this.navigation = const PapyrusNavigationPolicy(),
    this.resources = const PapyrusResourcePolicy(),
    this.javascript = const PapyrusJavaScriptPolicy(),
    this.storage = const PapyrusStoragePolicy(),
    this.media = const PapyrusMediaPolicy(),
    this.display = const PapyrusDisplayPolicy(),
    this.accessibility = const PapyrusAccessibilityPolicy(),
    this.interaction = const PapyrusInteractionPolicy(),
    this.platform = const PapyrusPlatformOptions(),
  });

  final PapyrusSecurityPolicy security;
  final PapyrusNavigationPolicy navigation;
  final PapyrusResourcePolicy resources;
  final PapyrusJavaScriptPolicy javascript;
  final PapyrusStoragePolicy storage;
  final PapyrusMediaPolicy media;
  final PapyrusDisplayPolicy display;
  final PapyrusAccessibilityPolicy accessibility;
  final PapyrusInteractionPolicy interaction;
  final PapyrusPlatformOptions platform;

  PapyrusConfiguration copyWith({
    PapyrusSecurityPolicy? security,
    PapyrusNavigationPolicy? navigation,
    PapyrusResourcePolicy? resources,
    PapyrusJavaScriptPolicy? javascript,
    PapyrusStoragePolicy? storage,
    PapyrusMediaPolicy? media,
    PapyrusDisplayPolicy? display,
    PapyrusAccessibilityPolicy? accessibility,
    PapyrusInteractionPolicy? interaction,
    PapyrusPlatformOptions? platform,
  }) {
    return PapyrusConfiguration(
      security: security ?? this.security,
      navigation: navigation ?? this.navigation,
      resources: resources ?? this.resources,
      javascript: javascript ?? this.javascript,
      storage: storage ?? this.storage,
      media: media ?? this.media,
      display: display ?? this.display,
      accessibility: accessibility ?? this.accessibility,
      interaction: interaction ?? this.interaction,
      platform: platform ?? this.platform,
    );
  }
}

class PapyrusProfiles {
  const PapyrusProfiles._();

  static PapyrusConfiguration lockedDown() => const PapyrusConfiguration();

  static PapyrusConfiguration documentViewer() {
    return const PapyrusConfiguration(
      resources: PapyrusResourcePolicy(
        remoteResources: PapyrusRemoteResourceMode.askHostApp,
      ),
      navigation: PapyrusNavigationPolicy(
        defaultDecision: PapyrusNavigationDecision.openExternally,
      ),
    );
  }

  static PapyrusConfiguration trustedAppContent() {
    return const PapyrusConfiguration(
      security: PapyrusSecurityPolicy(allowJavaScript: true),
      javascript: PapyrusJavaScriptPolicy(
        mode: PapyrusJavaScriptMode.restricted,
      ),
      resources: PapyrusResourcePolicy(
        remoteResources: PapyrusRemoteResourceMode.allowByHost,
      ),
      storage: PapyrusStoragePolicy(
        cookies: PapyrusCookiePolicy.allowByHost,
        localStorage: PapyrusStorageMode.enabled,
      ),
    );
  }

  static PapyrusConfiguration browserLike() {
    return const PapyrusConfiguration(
      security: PapyrusSecurityPolicy(
        allowJavaScript: true,
        allowPopups: true,
        allowMixedContent: true,
      ),
      navigation: PapyrusNavigationPolicy(
        defaultDecision: PapyrusNavigationDecision.allow,
        allowMainFrameNavigation: true,
        allowSubFrameNavigation: true,
      ),
      resources: PapyrusResourcePolicy(
        remoteResources: PapyrusRemoteResourceMode.allowAll,
      ),
      javascript: PapyrusJavaScriptPolicy(
        mode: PapyrusJavaScriptMode.unrestricted,
      ),
      storage: PapyrusStoragePolicy(
        cookies: PapyrusCookiePolicy.allow,
        localStorage: PapyrusStorageMode.enabled,
        ephemeral: false,
      ),
    );
  }

  static PapyrusConfiguration emailHtmlViewer() {
    return const PapyrusConfiguration(
      navigation: PapyrusNavigationPolicy(
        defaultDecision: PapyrusNavigationDecision.openExternally,
        requireUserGestureForExternalOpen: true,
        allowMainFrameNavigation: false,
        allowSubFrameNavigation: false,
      ),
      resources: PapyrusResourcePolicy(
        remoteResources: PapyrusRemoteResourceMode.block,
      ),
      javascript: PapyrusJavaScriptPolicy(mode: PapyrusJavaScriptMode.disabled),
      storage: PapyrusStoragePolicy(
        cookies: PapyrusCookiePolicy.block,
        localStorage: PapyrusStorageMode.disabled,
        ephemeral: true,
      ),
      display: PapyrusDisplayPolicy(autoHeight: true),
    );
  }
}

class PapyrusSecurityPolicy {
  const PapyrusSecurityPolicy({
    this.allowJavaScript = false,
    this.allowInlineMediaPlayback = false,
    this.allowFileAccess = false,
    this.allowUniversalAccessFromFileUrls = false,
    this.allowPopups = false,
    this.allowMixedContent = false,
    this.allowClipboardRead = false,
    this.allowClipboardWrite = false,
    this.allowGeolocation = false,
    this.allowCamera = false,
    this.allowMicrophone = false,
    this.allowProtectedMedia = false,
    this.enableContentIsolation = true,
    this.contentSecurityPolicy,
  });

  final bool allowJavaScript;
  final bool allowInlineMediaPlayback;
  final bool allowFileAccess;
  final bool allowUniversalAccessFromFileUrls;
  final bool allowPopups;
  final bool allowMixedContent;
  final bool allowClipboardRead;
  final bool allowClipboardWrite;
  final bool allowGeolocation;
  final bool allowCamera;
  final bool allowMicrophone;
  final bool allowProtectedMedia;
  final bool enableContentIsolation;
  final String? contentSecurityPolicy;
}

class PapyrusNavigationPolicy {
  const PapyrusNavigationPolicy({
    this.defaultDecision = PapyrusNavigationDecision.block,
    this.allowedSchemes = const {'https'},
    this.externalSchemes = const {'http', 'https', 'mailto', 'tel'},
    this.blockedSchemes = const {'javascript', 'data', 'file'},
    this.requireUserGestureForExternalOpen = true,
    this.allowMainFrameNavigation = false,
    this.allowSubFrameNavigation = false,
  });

  final PapyrusNavigationDecision defaultDecision;
  final Set<String> allowedSchemes;
  final Set<String> externalSchemes;
  final Set<String> blockedSchemes;
  final bool requireUserGestureForExternalOpen;
  final bool allowMainFrameNavigation;
  final bool allowSubFrameNavigation;

  PapyrusNavigationDecision resolve(PapyrusNavigationRequest request) {
    if (blockedSchemes.contains(request.uri.scheme)) {
      return PapyrusNavigationDecision.block;
    }
    if (request.isMainFrame && !allowMainFrameNavigation) {
      return defaultDecision;
    }
    if (!request.isMainFrame && !allowSubFrameNavigation) {
      return PapyrusNavigationDecision.block;
    }
    if (allowedSchemes.contains(request.uri.scheme)) {
      return PapyrusNavigationDecision.allow;
    }
    if (externalSchemes.contains(request.uri.scheme)) {
      if (requireUserGestureForExternalOpen && !request.hasUserGesture) {
        return PapyrusNavigationDecision.block;
      }
      return PapyrusNavigationDecision.openExternally;
    }
    return defaultDecision;
  }
}

class PapyrusNavigationRequest {
  const PapyrusNavigationRequest({
    required this.uri,
    required this.isMainFrame,
    required this.navigationType,
    required this.hasUserGesture,
  });

  final Uri uri;
  final bool isMainFrame;
  final PapyrusNavigationType navigationType;
  final bool hasUserGesture;
}

class PapyrusResourcePolicy {
  const PapyrusResourcePolicy({
    this.remoteResources = PapyrusRemoteResourceMode.block,
    this.allowedHosts = const {},
    this.allowedSchemes = const {'https'},
    this.blockedResourceTypes = const {},
    this.virtualResourceOrigin,
    this.enableRequestInterception = true,
  });

  final PapyrusRemoteResourceMode remoteResources;
  final Set<String> allowedHosts;
  final Set<String> allowedSchemes;
  final Set<PapyrusResourceType> blockedResourceTypes;
  final Uri? virtualResourceOrigin;
  final bool enableRequestInterception;

  bool allows(Uri uri, {PapyrusResourceType type = PapyrusResourceType.other}) {
    if (blockedResourceTypes.contains(type)) {
      return false;
    }
    if (!allowedSchemes.contains(uri.scheme)) {
      return false;
    }
    return switch (remoteResources) {
      PapyrusRemoteResourceMode.block => false,
      PapyrusRemoteResourceMode.allowAll => true,
      PapyrusRemoteResourceMode.allowByHost => allowedHosts.contains(uri.host),
      PapyrusRemoteResourceMode.askHostApp => false,
    };
  }
}

class PapyrusJavaScriptPolicy {
  const PapyrusJavaScriptPolicy({
    this.mode = PapyrusJavaScriptMode.disabled,
    this.allowedChannels = const {},
    this.allowUserScripts = false,
    this.injectedScripts = const [],
  });

  final PapyrusJavaScriptMode mode;
  final Set<String> allowedChannels;
  final bool allowUserScripts;
  final List<PapyrusUserScript> injectedScripts;
}

class PapyrusUserScript {
  const PapyrusUserScript(this.source);

  final String source;
}

class PapyrusStoragePolicy {
  const PapyrusStoragePolicy({
    this.cookies = PapyrusCookiePolicy.block,
    this.localStorage = PapyrusStorageMode.disabled,
    this.cache = PapyrusCacheMode.defaultMode,
    this.ephemeral = true,
    this.partitionId,
  });

  final PapyrusCookiePolicy cookies;
  final PapyrusStorageMode localStorage;
  final PapyrusCacheMode cache;
  final bool ephemeral;
  final String? partitionId;
}

class PapyrusMediaPolicy {
  const PapyrusMediaPolicy({
    this.autoPlay = false,
    this.inlinePlayback = false,
    this.requireUserGesture = true,
    this.allowFullscreen = false,
  });

  final bool autoPlay;
  final bool inlinePlayback;
  final bool requireUserGesture;
  final bool allowFullscreen;
}

class PapyrusDisplayPolicy {
  const PapyrusDisplayPolicy({
    this.autoHeight = false,
    this.minimumHeight,
    this.maximumHeight,
    this.zoomEnabled = true,
    this.textZoom = 1.0,
    this.backgroundColor,
    this.darkMode = PapyrusDarkMode.system,
    this.viewport = const PapyrusViewportPolicy(),
    this.measurement = const PapyrusMeasurementPolicy(),
  });

  final bool autoHeight;
  final double? minimumHeight;
  final double? maximumHeight;
  final bool zoomEnabled;
  final double textZoom;
  final int? backgroundColor;
  final PapyrusDarkMode darkMode;
  final PapyrusViewportPolicy viewport;
  final PapyrusMeasurementPolicy measurement;
}

class PapyrusViewportPolicy {
  const PapyrusViewportPolicy({this.width = 'device-width', this.scale = 1.0});

  final String width;
  final double scale;
}

class PapyrusMeasurementPolicy {
  const PapyrusMeasurementPolicy({
    this.observeMutations = true,
    this.debounceMillis = 50,
  });

  final bool observeMutations;
  final int debounceMillis;
}

class PapyrusAccessibilityPolicy {
  const PapyrusAccessibilityPolicy({this.enableNativeSemantics = true});

  final bool enableNativeSemantics;
}

class PapyrusInteractionPolicy {
  const PapyrusInteractionPolicy({
    this.allowTextSelection = true,
    this.allowContextMenu = true,
    this.allowLongPress = true,
  });

  final bool allowTextSelection;
  final bool allowContextMenu;
  final bool allowLongPress;
}

class PapyrusPlatformOptions {
  const PapyrusPlatformOptions({
    this.debuggingEnabled = false,
    this.hardwareAcceleration = PapyrusHardwareAccelerationMode.auto,
  });

  final bool debuggingEnabled;
  final PapyrusHardwareAccelerationMode hardwareAcceleration;
}

class PapyrusVirtualResource {
  const PapyrusVirtualResource({
    required this.uri,
    required this.bytes,
    required this.mimeType,
    this.headers = const {},
  });

  final Uri uri;
  final Uint8List bytes;
  final String mimeType;
  final Map<String, String> headers;

  JsonMap toMap() => {
    'uri': uri.toString(),
    'bytes': bytes.toList(),
    'mimeType': mimeType,
    'headers': headers,
  };
}

class PapyrusResourceRequest {
  const PapyrusResourceRequest({
    required this.uri,
    required this.method,
    required this.headers,
    required this.resourceType,
    required this.isMainFrame,
  });

  final Uri uri;
  final String method;
  final Map<String, String> headers;
  final PapyrusResourceType resourceType;
  final bool isMainFrame;

  JsonMap toMap() => {
    'uri': uri.toString(),
    'method': method,
    'headers': headers,
    'resourceType': resourceType.name,
    'isMainFrame': isMainFrame,
  };

  static PapyrusResourceRequest fromMap(Map<Object?, Object?> map) {
    return PapyrusResourceRequest(
      uri: Uri.parse(map['uri'] as String? ?? ''),
      method: map['method'] as String? ?? 'GET',
      headers: _stringMapFromObject(map['headers']),
      resourceType: _resourceTypeFromName(
        map['resourceType'] as String? ?? PapyrusResourceType.other.name,
      ),
      isMainFrame: map['isMainFrame'] as bool? ?? false,
    );
  }
}

sealed class PapyrusResourceDecision {
  const PapyrusResourceDecision();
}

class PapyrusAllowResource extends PapyrusResourceDecision {
  const PapyrusAllowResource();
}

class PapyrusBlockResource extends PapyrusResourceDecision {
  const PapyrusBlockResource();
}

class PapyrusRespondWithResource extends PapyrusResourceDecision {
  const PapyrusRespondWithResource(this.response);

  final PapyrusResourceResponse response;
}

JsonMap papyrusResourceDecisionToMap(PapyrusResourceDecision decision) {
  return switch (decision) {
    PapyrusAllowResource() => {'decision': 'allow'},
    PapyrusBlockResource() => {'decision': 'block'},
    PapyrusRespondWithResource(response: final response) => {
      'decision': 'respond',
      'response': response.toMap(),
    },
  };
}

PapyrusResourceDecision papyrusResourceDecisionFromMap(
  Map<Object?, Object?> map,
) {
  return switch (map['decision'] as String? ?? 'allow') {
    'block' => const PapyrusBlockResource(),
    'respond' => PapyrusRespondWithResource(
      PapyrusResourceResponse.fromMap(
        map['response'] as Map<Object?, Object?>? ?? const {},
      ),
    ),
    _ => const PapyrusAllowResource(),
  };
}

class PapyrusResourceResponse {
  const PapyrusResourceResponse({
    required this.bytes,
    required this.mimeType,
    this.statusCode = 200,
    this.headers = const {},
  });

  final Uint8List bytes;
  final String mimeType;
  final int statusCode;
  final Map<String, String> headers;

  JsonMap toMap() => {
    'bytes': bytes.toList(),
    'mimeType': mimeType,
    'statusCode': statusCode,
    'headers': headers,
  };

  static PapyrusResourceResponse fromMap(Map<Object?, Object?> map) {
    return PapyrusResourceResponse(
      bytes: Uint8List.fromList(
        ((map['bytes'] as List<Object?>?) ?? const <Object?>[])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(),
      ),
      mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
      statusCode: (map['statusCode'] as num?)?.toInt() ?? 200,
      headers: _stringMapFromObject(map['headers']),
    );
  }
}

abstract class PapyrusVirtualResourceProvider {
  Future<PapyrusResourceResponse?> resolve(PapyrusResourceRequest request);
}

class PapyrusResourceRegistry {
  final _providers = <PapyrusVirtualResourceProvider>[];

  List<PapyrusVirtualResourceProvider> get providers =>
      List.unmodifiable(_providers);

  void register(PapyrusVirtualResourceProvider provider) {
    if (!_providers.contains(provider)) {
      _providers.add(provider);
    }
  }

  void unregister(PapyrusVirtualResourceProvider provider) {
    _providers.remove(provider);
  }

  Future<PapyrusResourceResponse?> resolve(
    PapyrusResourceRequest request,
  ) async {
    for (final provider in _providers) {
      final response = await provider.resolve(request);
      if (response != null) {
        return response;
      }
    }
    return null;
  }
}

typedef PapyrusNavigationResolver =
    Future<PapyrusNavigationDecision> Function(
      PapyrusNavigationRequest request,
    );

typedef PapyrusResourceResolver =
    Future<PapyrusResourceDecision> Function(PapyrusResourceRequest request);

class PapyrusDownloadRequest {
  const PapyrusDownloadRequest({
    required this.uri,
    this.mimeType,
    this.suggestedFilename,
    this.contentLength,
  });

  final Uri uri;
  final String? mimeType;
  final String? suggestedFilename;
  final int? contentLength;
}

class PapyrusPermissionRequest {
  const PapyrusPermissionRequest({
    required this.uri,
    required this.permissions,
  });

  final Uri uri;
  final Set<PapyrusPermissionType> permissions;
}

abstract class PapyrusEvent {
  const PapyrusEvent();
}

class PapyrusPageStartedEvent extends PapyrusEvent {
  const PapyrusPageStartedEvent({this.uri});

  final Uri? uri;
}

class PapyrusPageFinishedEvent extends PapyrusEvent {
  const PapyrusPageFinishedEvent({this.uri});

  final Uri? uri;
}

class PapyrusProgressEvent extends PapyrusEvent {
  const PapyrusProgressEvent(this.progress);

  final double progress;
}

class PapyrusErrorEvent extends PapyrusEvent {
  const PapyrusErrorEvent({
    required this.code,
    required this.message,
    this.uri,
    this.isMainFrame = true,
  });

  final PapyrusErrorCode code;
  final String message;
  final Uri? uri;
  final bool isMainFrame;
}

class PapyrusContentSizeChangedEvent extends PapyrusEvent {
  const PapyrusContentSizeChangedEvent(this.size);

  final PapyrusContentSize size;
}

class PapyrusContentSize {
  const PapyrusContentSize({required this.width, required this.height});

  final double width;
  final double height;
}

class PapyrusConsoleMessage {
  const PapyrusConsoleMessage(this.message);

  final String message;
}

class PapyrusWebMessage {
  const PapyrusWebMessage(this.name, this.payload);

  final String name;
  final Object? payload;
}

class PapyrusSnapshotOptions {
  const PapyrusSnapshotOptions({this.width, this.height});

  final double? width;
  final double? height;
}

class PapyrusPrintOptions {
  const PapyrusPrintOptions({this.jobName});

  final String? jobName;
}

class PapyrusStorageClearOptions {
  const PapyrusStorageClearOptions({
    this.cookies = true,
    this.localStorage = true,
    this.cache = true,
  });

  final bool cookies;
  final bool localStorage;
  final bool cache;
}

class PapyrusPlatformCapabilities {
  const PapyrusPlatformCapabilities({
    required this.supportsResourceInterception,
    required this.supportsVirtualSchemes,
    required this.supportsEphemeralStorage,
    required this.supportsPrint,
    required this.supportsSnapshot,
    required this.supportsAutoHeight,
    required this.supportsDarkMode,
    required this.supportsDownloadInterception,
    required this.supportsPermissionInterception,
  });

  final bool supportsResourceInterception;
  final bool supportsVirtualSchemes;
  final bool supportsEphemeralStorage;
  final bool supportsPrint;
  final bool supportsSnapshot;
  final bool supportsAutoHeight;
  final bool supportsDarkMode;
  final bool supportsDownloadInterception;
  final bool supportsPermissionInterception;

  @override
  bool operator ==(Object other) {
    return other is PapyrusPlatformCapabilities &&
        supportsResourceInterception == other.supportsResourceInterception &&
        supportsVirtualSchemes == other.supportsVirtualSchemes &&
        supportsEphemeralStorage == other.supportsEphemeralStorage &&
        supportsPrint == other.supportsPrint &&
        supportsSnapshot == other.supportsSnapshot &&
        supportsAutoHeight == other.supportsAutoHeight &&
        supportsDarkMode == other.supportsDarkMode &&
        supportsDownloadInterception == other.supportsDownloadInterception &&
        supportsPermissionInterception == other.supportsPermissionInterception;
  }

  @override
  int get hashCode => Object.hash(
    supportsResourceInterception,
    supportsVirtualSchemes,
    supportsEphemeralStorage,
    supportsPrint,
    supportsSnapshot,
    supportsAutoHeight,
    supportsDarkMode,
    supportsDownloadInterception,
    supportsPermissionInterception,
  );
}

  JsonMap papyrusConfigurationToMap(
    PapyrusConfiguration configuration, {
    bool resourceResolverEnabled = false,
  }) => {
    'allowJavaScript':
      configuration.security.allowJavaScript ||
      configuration.javascript.mode != PapyrusJavaScriptMode.disabled,
    'allowInlineMediaPlayback': configuration.security.allowInlineMediaPlayback,
    'allowFileAccess': configuration.security.allowFileAccess,
    'allowUniversalAccessFromFileUrls':
      configuration.security.allowUniversalAccessFromFileUrls,
    'allowPopups': configuration.security.allowPopups,
    'allowMixedContent': configuration.security.allowMixedContent,
    'allowClipboardRead': configuration.security.allowClipboardRead,
    'allowClipboardWrite': configuration.security.allowClipboardWrite,
    'allowGeolocation': configuration.security.allowGeolocation,
    'allowCamera': configuration.security.allowCamera,
    'allowMicrophone': configuration.security.allowMicrophone,
    'allowProtectedMedia': configuration.security.allowProtectedMedia,
    'enableContentIsolation': configuration.security.enableContentIsolation,
    'contentSecurityPolicy': configuration.security.contentSecurityPolicy,
    'navigationDefaultDecision': configuration.navigation.defaultDecision.name,
    'navigationAllowedSchemes': configuration.navigation.allowedSchemes.toList(),
    'navigationExternalSchemes': configuration.navigation.externalSchemes
      .toList(),
    'navigationBlockedSchemes': configuration.navigation.blockedSchemes.toList(),
    'requireUserGestureForExternalOpen':
      configuration.navigation.requireUserGestureForExternalOpen,
    'allowMainFrameNavigation': configuration.navigation.allowMainFrameNavigation,
    'allowSubFrameNavigation': configuration.navigation.allowSubFrameNavigation,
    'remoteResources': configuration.resources.remoteResources.name,
    'allowedHosts': configuration.resources.allowedHosts.toList(),
    'allowedSchemes': configuration.resources.allowedSchemes.toList(),
    'blockedResourceTypes': configuration.resources.blockedResourceTypes
      .map((type) => type.name)
      .toList(),
    'virtualResourceScheme':
      configuration.resources.virtualResourceOrigin?.scheme ??
      'papyrus-resource',
    'enableRequestInterception':
      configuration.resources.enableRequestInterception,
    'javaScriptMode': configuration.javascript.mode.name,
    'allowedJavaScriptChannels': configuration.javascript.allowedChannels
      .toList(),
    'allowUserScripts': configuration.javascript.allowUserScripts,
    'injectedScripts': configuration.javascript.injectedScripts
      .map((script) => script.source)
      .toList(),
    'cookiePolicy': configuration.storage.cookies.name,
    'localStorage': configuration.storage.localStorage.name,
    'cacheMode': configuration.storage.cache.name,
    'ephemeral': configuration.storage.ephemeral,
    'partitionId': configuration.storage.partitionId,
    'mediaAutoPlay': configuration.media.autoPlay,
    'inlinePlayback': configuration.media.inlinePlayback,
    'requireMediaUserGesture': configuration.media.requireUserGesture,
    'allowFullscreen': configuration.media.allowFullscreen,
    'autoHeight': configuration.display.autoHeight,
    'minimumHeight': configuration.display.minimumHeight,
    'maximumHeight': configuration.display.maximumHeight,
    'zoomEnabled': configuration.display.zoomEnabled,
    'textZoom': configuration.display.textZoom,
    'backgroundColor': configuration.display.backgroundColor,
    'darkMode': configuration.display.darkMode.name,
    'viewportWidth': configuration.display.viewport.width,
    'viewportScale': configuration.display.viewport.scale,
    'observeMutations': configuration.display.measurement.observeMutations,
    'measurementDebounceMillis': configuration.display.measurement.debounceMillis,
    'enableNativeSemantics': configuration.accessibility.enableNativeSemantics,
    'allowTextSelection': configuration.interaction.allowTextSelection,
    'allowContextMenu': configuration.interaction.allowContextMenu,
    'allowLongPress': configuration.interaction.allowLongPress,
    'resourceResolverEnabled': resourceResolverEnabled,
    'debuggingEnabled': configuration.platform.debuggingEnabled,
    'hardwareAcceleration': configuration.platform.hardwareAcceleration.name,
  };

PapyrusResourceType _resourceTypeFromName(String name) {
  return PapyrusResourceType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => PapyrusResourceType.other,
  );
}

Map<String, String> _stringMapFromObject(Object? value) {
  if (value is Map<Object?, Object?>) {
    return value.map(
      (key, entry) => MapEntry(key?.toString() ?? '', entry?.toString() ?? ''),
    );
  }
  return const {};
}

class PapyrusHtmlComposer {
  const PapyrusHtmlComposer._();

  static const _viewportMeta =
      '<meta name="viewport" content="width=device-width, initial-scale=1">';

  static String ensureDocument(String html) {
    return _ensureViewportMeta(_ensureHtmlShell(html));
  }

  static String injectContentSecurityPolicy(String html, String policy) {
    html = ensureDocument(html);
    final meta =
        '<meta http-equiv="Content-Security-Policy" content="${_escape(policy)}">';
    final headPattern = RegExp(r'<head(\s[^>]*)?>', caseSensitive: false);
    final headMatch = headPattern.firstMatch(html);
    if (headMatch != null) {
      return html.replaceRange(headMatch.end, headMatch.end, meta);
    }
    final htmlPattern = RegExp(r'<html(\s[^>]*)?>', caseSensitive: false);
    final htmlMatch = htmlPattern.firstMatch(html);
    if (htmlMatch != null) {
      return html.replaceRange(
        htmlMatch.end,
        htmlMatch.end,
        '<head>$meta</head>',
      );
    }
    return '<!doctype html><html><head>$meta</head><body>$html</body></html>';
  }

  static String _escape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static String _ensureHtmlShell(String html) {
    final doctypePattern = RegExp(r'<!doctype\s+html', caseSensitive: false);
    if (doctypePattern.hasMatch(html)) {
      return html;
    }

    final htmlPattern = RegExp(r'<html(\s[^>]*)?>', caseSensitive: false);
    if (htmlPattern.hasMatch(html)) {
      return html;
    }

    final hasHead = RegExp(
      r'<head(\s[^>]*)?>',
      caseSensitive: false,
    ).hasMatch(html);
    final hasBody = RegExp(
      r'<body(\s[^>]*)?>',
      caseSensitive: false,
    ).hasMatch(html);
    if (hasHead || hasBody) {
      return '<!doctype html><html>$html</html>';
    }

    return '<!doctype html><html><head></head><body>$html</body></html>';
  }

  static String _ensureViewportMeta(String html) {
    final viewportPattern = RegExp(
      "<meta\\s+[^>]*name\\s*=\\s*['\"]viewport['\"][^>]*>",
      caseSensitive: false,
    );
    if (viewportPattern.hasMatch(html)) {
      return html;
    }

    final headPattern = RegExp(r'<head(\s[^>]*)?>', caseSensitive: false);
    final headMatch = headPattern.firstMatch(html);
    if (headMatch != null) {
      return html.replaceRange(headMatch.end, headMatch.end, _viewportMeta);
    }

    final htmlPattern = RegExp(r'<html(\s[^>]*)?>', caseSensitive: false);
    final htmlMatch = htmlPattern.firstMatch(html);
    if (htmlMatch != null) {
      return html.replaceRange(
        htmlMatch.end,
        htmlMatch.end,
        '<head>$_viewportMeta</head>',
      );
    }

    return '<!doctype html><html><head>$_viewportMeta</head><body>$html</body></html>';
  }
}

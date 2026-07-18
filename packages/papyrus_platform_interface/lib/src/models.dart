import 'dart:typed_data';

/// A convenience alias for a JSON-compatible map with string keys.
typedef JsonMap = Map<String, Object?>;

/// The type of navigation that triggered a [PapyrusNavigationRequest].
enum PapyrusNavigationType {
  /// Navigation initiated by the user clicking a link.
  linkClicked,

  /// Navigation initiated by a form submission.
  formSubmitted,

  /// Navigation initiated by pressing the back or forward button.
  backForward,

  /// Navigation initiated by reloading the current page.
  reload,

  /// Navigation initiated programmatically (e.g. via JavaScript or [PapyrusController.load]).
  programmatic,

  /// Navigation type that does not fit any of the above categories.
  other,
}

/// The decision returned by a navigation resolver to determine what happens
/// when the webview attempts to navigate to a new URL.
enum PapyrusNavigationDecision {
  /// Allow the navigation to proceed inside the webview.
  allow,

  /// Block the navigation entirely.
  block,

  /// Open the URL in an external browser or application.
  openExternally,

  /// Treat the URL as a file download.
  download,
}

/// The type of a sub-resource requested by the webview.
enum PapyrusResourceType {
  /// A full HTML document resource.
  document,

  /// A CSS stylesheet resource.
  stylesheet,

  /// An image resource.
  image,

  /// A web font resource.
  font,

  /// A JavaScript script resource.
  script,

  /// An XMLHttpRequest or Fetch API resource.
  xhr,

  /// An audio or video media resource.
  media,

  /// A resource loaded inside an iframe.
  iframe,

  /// A resource type that does not fit any of the above categories.
  other,
}

/// Controls how the webview handles remote (non-virtual) sub-resource requests.
enum PapyrusRemoteResourceMode {
  /// Block all remote resource requests.
  block,

  /// Allow all remote resource requests unconditionally.
  allowAll,

  /// Allow only requests whose host is in [PapyrusResourcePolicy.allowedHosts].
  allowByHost,

  /// Forward remote resource requests to the host app's resource resolver.
  askHostApp,
}

/// Controls which JavaScript execution features are enabled in the webview.
enum PapyrusJavaScriptMode {
  /// JavaScript execution is disabled entirely.
  disabled,

  /// JavaScript may run but communication with the host app is limited
  /// to channels explicitly registered via [PapyrusJavaScriptPolicy.allowedChannels].
  restricted,

  /// JavaScript execution is fully unrestricted.
  unrestricted,
}

/// Controls cookie storage and transmission for the webview session.
enum PapyrusCookiePolicy {
  /// Block all cookies.
  block,

  /// Allow cookies for all origins.
  allow,

  /// Allow cookies only for hosts listed in [PapyrusStoragePolicy.cookies].
  allowByHost,
}

/// Controls whether the webview can use persistent local storage (localStorage / IndexedDB).
enum PapyrusStorageMode {
  /// Local storage is disabled.
  disabled,

  /// Local storage is enabled.
  enabled,
}

/// Controls HTTP caching behaviour for the webview.
enum PapyrusCacheMode {
  /// Use the platform's default caching behaviour (respects HTTP cache headers).
  defaultMode,

  /// Disable the HTTP cache; always fetch resources from the network.
  noCache,

  /// Load resources from the cache only; never make network requests.
  cacheOnly,
}

/// A browser permission type that the web page may request from the user.
enum PapyrusPermissionType {
  /// Access to the device camera.
  camera,

  /// Access to the device microphone.
  microphone,

  /// Access to the device's geographic location.
  geolocation,

  /// Permission to display push notifications.
  notifications,

  /// Permission to read from the system clipboard.
  clipboardRead,

  /// Permission to write to the system clipboard.
  clipboardWrite,

  /// Permission to play DRM-protected media.
  protectedMedia,

  /// Permission to open a native file-chooser dialog.
  fileChooser,
}

/// The decision made in response to a [PapyrusPermissionRequest].
enum PapyrusPermissionDecision {
  /// Grant the requested permissions.
  grant,

  /// Deny the requested permissions.
  deny,

  /// Forward the request to the host application for a user-facing prompt.
  promptHostApp,
}

/// The decision made in response to a download request from the webview.
enum PapyrusDownloadDecision {
  /// Block the download entirely.
  block,

  /// Let the operating system's default download manager handle the download.
  allowSystemDownload,

  /// Hand the download URL to the host application to handle as it sees fit.
  handToHostApp,
}

/// Error codes reported by [PapyrusException] and [PapyrusErrorEvent].
enum PapyrusErrorCode {
  /// An error occurred for which no more specific code is available.
  unknown,

  /// A navigation attempt was blocked by the active [PapyrusNavigationPolicy].
  navigationBlocked,

  /// A sub-resource request was blocked by the active [PapyrusResourcePolicy].
  resourceBlocked,

  /// A network-level failure occurred (e.g. DNS resolution or connection error).
  networkFailed,

  /// An SSL/TLS certificate error occurred.
  sslFailed,

  /// The page or resource load timed out.
  timeout,

  /// The webview renderer process crashed or was terminated.
  rendererCrashed,

  /// The operation is not supported by the current platform implementation.
  unsupportedPlatformFeature,

  /// The [PapyrusLoadRequest] was invalid or malformed.
  invalidLoadRequest,

  /// The native webview component could not be created or is unavailable.
  webViewUnavailable,
}

/// Controls whether the webview renders content in dark mode.
enum PapyrusDarkMode {
  /// Follow the host system's light/dark mode setting.
  system,

  /// Always render in light mode.
  light,

  /// Always render in dark mode.
  dark,
}

/// Controls hardware acceleration for the webview renderer.
enum PapyrusHardwareAccelerationMode {
  /// Let the platform decide whether to use hardware acceleration.
  auto,

  /// Force hardware-accelerated rendering.
  hardware,

  /// Force software rendering (disables GPU compositing).
  software,
}

/// An exception thrown by Papyrus operations.
///
/// Contains a machine-readable [code] for programmatic handling and a
/// human-readable [message] for logging.
class PapyrusException implements Exception {
  /// Creates a [PapyrusException] with the given [code] and [message].
  const PapyrusException(this.code, this.message, {this.uri});

  final PapyrusErrorCode code;
  final String message;
  final Uri? uri;

  @override
  String toString() => 'PapyrusException(${code.name}, $message)';
}

/// The base class for all webview load requests.
///
/// Use one of the concrete subtypes:
/// - [PapyrusHtmlRequest] — load an inline HTML string
/// - [PapyrusUriRequest] — navigate to a URL
/// - [PapyrusFileRequest] — load a local file
/// - [PapyrusDataRequest] — load raw bytes with a MIME type
sealed class PapyrusLoadRequest {
  const PapyrusLoadRequest();

  String get type;

  JsonMap toMap();

  void validate();
}

/// A load request that renders an inline HTML string in the webview.
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

/// A load request that navigates the webview to a URL.
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

/// A load request that loads a local file from the device filesystem.
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

/// A load request that renders raw binary data with a given MIME type.
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

/// Optional metadata that describes the origin and type of loaded content.
///
/// Attach to an [PapyrusHtmlRequest] via [PapyrusHtmlRequest.metadata] to
/// provide additional context to the platform implementation.
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

/// The top-level configuration object that controls all webview behaviour.
///
/// The default constructor produces a fully locked-down configuration suitable
/// for secure document rendering. Use [PapyrusProfiles] for common presets.
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
    this.userAgent,
  });

  /// Security settings such as JavaScript enablement and content isolation.
  final PapyrusSecurityPolicy security;

  /// Rules governing which URLs the webview may navigate to.
  final PapyrusNavigationPolicy navigation;

  /// Rules governing which sub-resources the webview may load.
  final PapyrusResourcePolicy resources;

  /// JavaScript execution policy including allowed message channels.
  final PapyrusJavaScriptPolicy javascript;

  /// Cookie, localStorage and cache settings.
  final PapyrusStoragePolicy storage;

  /// Media autoplay and inline playback settings.
  final PapyrusMediaPolicy media;

  /// Display options such as auto-height, zoom, dark mode, and viewport.
  final PapyrusDisplayPolicy display;

  /// Accessibility options for native semantics bridges.
  final PapyrusAccessibilityPolicy accessibility;

  /// User interaction options such as text selection and context menu.
  final PapyrusInteractionPolicy interaction;

  /// Low-level platform-specific options.
  final PapyrusPlatformOptions platform;

  /// A custom User-Agent string applied to the whole webview session.
  ///
  /// When non-null and non-empty, the native engine's user agent is overridden
  /// for all requests (including sub-resources and XHR/fetch) and
  /// `navigator.userAgent`. When null (the default), the platform's built-in
  /// user agent is used unchanged.
  final String? userAgent;

  /// Returns a copy of this configuration with the given fields replaced.
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
    String? userAgent,
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
      userAgent: userAgent ?? this.userAgent,
    );
  }
}

/// Predefined [PapyrusConfiguration] presets for common use-cases.
class PapyrusProfiles {
  const PapyrusProfiles._();

  /// A fully locked-down configuration that allows no JavaScript or navigation.
  static PapyrusConfiguration lockedDown() => const PapyrusConfiguration();

  /// A read-only document viewer that opens external links outside the webview.
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

  /// A balanced configuration for trusted first-party content with restricted JavaScript.
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

  /// A permissive browser-like configuration with JavaScript, cookies, and navigation enabled.
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

  /// A strict configuration for safely displaying untrusted HTML email content.
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

/// Security policy controlling JavaScript, file access, popups, and other
/// sensitive browser capabilities.
class PapyrusSecurityPolicy {
  /// Creates a [PapyrusSecurityPolicy].
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

/// Policy that controls which navigations the webview is allowed to perform.
class PapyrusNavigationPolicy {
  /// Creates a [PapyrusNavigationPolicy].
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

/// Describes a navigation attempt in the webview, passed to a
/// [PapyrusNavigationResolver] for policy evaluation.
class PapyrusNavigationRequest {
  /// Creates a [PapyrusNavigationRequest].
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

  JsonMap toMap() => {
    'uri': uri.toString(),
    'isMainFrame': isMainFrame,
    'navigationType': navigationType.name,
    'hasUserGesture': hasUserGesture,
  };

  static PapyrusNavigationRequest fromMap(Map<Object?, Object?> map) {
    return PapyrusNavigationRequest(
      uri: Uri.parse(map['uri'] as String? ?? ''),
      isMainFrame: map['isMainFrame'] as bool? ?? false,
      navigationType: _navigationTypeFromName(
        map['navigationType'] as String? ?? PapyrusNavigationType.other.name,
      ),
      hasUserGesture: map['hasUserGesture'] as bool? ?? false,
    );
  }
}

/// Policy that controls how the webview loads sub-resources such as images,
/// scripts, and stylesheets.
class PapyrusResourcePolicy {
  /// Creates a [PapyrusResourcePolicy].
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

/// Policy governing JavaScript execution and host-app channel communication.
class PapyrusJavaScriptPolicy {
  /// Creates a [PapyrusJavaScriptPolicy].
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

/// A JavaScript snippet that is injected into every page loaded by the webview.
class PapyrusUserScript {
  /// Creates a [PapyrusUserScript] with the given [source] code.
  const PapyrusUserScript(this.source);

  /// The JavaScript source code to inject.
  final String source;
}

/// Policy controlling cookie storage, local storage, and HTTP cache behaviour.
class PapyrusStoragePolicy {
  /// Creates a [PapyrusStoragePolicy].
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

/// Policy controlling media autoplay, inline playback, and fullscreen.
class PapyrusMediaPolicy {
  /// Creates a [PapyrusMediaPolicy].
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

/// Policy controlling display options such as auto-height, zoom, dark mode,
/// text zoom, and background colour.
class PapyrusDisplayPolicy {
  /// Creates a [PapyrusDisplayPolicy].
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

/// Viewport meta-tag settings injected into loaded HTML documents.
class PapyrusViewportPolicy {
  /// Creates a [PapyrusViewportPolicy].
  const PapyrusViewportPolicy({this.width = 'device-width', this.scale = 1.0});

  /// The viewport width value (e.g. `'device-width'` or a pixel amount).
  final String width;

  /// The initial zoom scale (1.0 = no zoom).
  final double scale;
}

/// Policy controlling content-size measurement and mutation observation.
class PapyrusMeasurementPolicy {
  /// Creates a [PapyrusMeasurementPolicy].
  const PapyrusMeasurementPolicy({
    this.observeMutations = true,
    this.debounceMillis = 50,
  });

  final bool observeMutations;
  final int debounceMillis;
}

/// Accessibility options for the webview.
class PapyrusAccessibilityPolicy {
  /// Creates a [PapyrusAccessibilityPolicy].
  const PapyrusAccessibilityPolicy({this.enableNativeSemantics = true});

  /// Whether to enable the native accessibility semantics bridge.
  final bool enableNativeSemantics;
}

/// Policy controlling pointer and gesture interaction with the webview content.
class PapyrusInteractionPolicy {
  /// Creates a [PapyrusInteractionPolicy].
  const PapyrusInteractionPolicy({
    this.allowTextSelection = true,
    this.allowContextMenu = true,
    this.allowLongPress = true,
  });

  final bool allowTextSelection;
  final bool allowContextMenu;
  final bool allowLongPress;
}

/// Low-level platform-specific options not covered by the cross-platform policy model.
class PapyrusPlatformOptions {
  /// Creates a [PapyrusPlatformOptions].
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

JsonMap papyrusNavigationDecisionToMap(PapyrusNavigationDecision decision) => {
  'decision': decision.name,
};

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
  'userAgent': configuration.userAgent,
};

PapyrusResourceType _resourceTypeFromName(String name) {
  return PapyrusResourceType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => PapyrusResourceType.other,
  );
}

PapyrusNavigationType _navigationTypeFromName(String name) {
  return PapyrusNavigationType.values.firstWhere(
    (type) => type.name == name,
    orElse: () => PapyrusNavigationType.other,
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

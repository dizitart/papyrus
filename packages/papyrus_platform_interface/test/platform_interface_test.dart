import 'dart:typed_data';

import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    PapyrusPlatform.instance = _FakePapyrusPlatform();
  });

  group('platform registration', () {
    test('allows implementations that extend the platform interface', () {
      final platform = _FakePapyrusPlatform();

      PapyrusPlatform.instance = platform;

      expect(PapyrusPlatform.instance, same(platform));
    });
  });

  group('load requests', () {
    test('HTML request serializes metadata and virtual resources', () {
      final request = PapyrusHtmlRequest(
        html: '<p>Hello</p>',
        baseUri: Uri.parse('papyrus-resource://message/1/'),
        metadata: const PapyrusContentMetadata(
          contentType: 'text/html',
          source: 'email',
          identifier: 'm-1',
        ),
        virtualResources: [
          PapyrusVirtualResource(
            uri: Uri.parse('papyrus-resource://message/1/logo.png'),
            bytes: Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png',
            headers: const {'cache-control': 'no-store'},
          ),
        ],
      );

      expect(request.validate, returnsNormally);
      expect(request.toMap(), {
        'type': 'html',
        'html':
            '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><p>Hello</p></body></html>',
        'baseUri': 'papyrus-resource://message/1/',
        'metadata': {
          'contentType': 'text/html',
          'source': 'email',
          'identifier': 'm-1',
          'extra': <String, String>{},
        },
        'virtualResources': [
          {
            'uri': 'papyrus-resource://message/1/logo.png',
            'bytes': [1, 2, 3],
            'mimeType': 'image/png',
            'headers': {'cache-control': 'no-store'},
          },
        ],
      });
    });

    test('invalid file request is rejected before platform dispatch', () {
      const request = PapyrusFileRequest(absolutePath: 'relative/file.html');

      expect(request.validate, throwsA(isA<ArgumentError>()));
    });
  });

  group('configuration defaults', () {
    test('default configuration is conservative', () {
      const config = PapyrusConfiguration();

      expect(config.security.allowJavaScript, isFalse);
      expect(config.security.allowPopups, isFalse);
      expect(config.security.allowFileAccess, isFalse);
      expect(
        config.navigation.defaultDecision,
        PapyrusNavigationDecision.block,
      );
      expect(config.storage.cookies, PapyrusCookiePolicy.block);
      expect(config.storage.ephemeral, isTrue);
      expect(config.media.requireUserGesture, isTrue);
      expect(config.resources.remoteResources, PapyrusRemoteResourceMode.block);
      expect(
        config.platform.hardwareAcceleration,
        PapyrusHardwareAccelerationMode.auto,
      );
    });

    test('email profile blocks scripts, storage, and remote resources', () {
      final config = PapyrusProfiles.emailHtmlViewer();

      expect(config.javascript.mode, PapyrusJavaScriptMode.disabled);
      expect(config.resources.remoteResources, PapyrusRemoteResourceMode.block);
      expect(config.storage.localStorage, PapyrusStorageMode.disabled);
      expect(config.storage.cookies, PapyrusCookiePolicy.block);
      expect(
        config.navigation.defaultDecision,
        PapyrusNavigationDecision.openExternally,
      );
    });

    test('configuration serializer exposes the generic policy surface', () {
      final map = papyrusConfigurationToMap(
        PapyrusConfiguration(
          security: const PapyrusSecurityPolicy(
            allowJavaScript: true,
            allowInlineMediaPlayback: true,
            allowFileAccess: true,
            allowUniversalAccessFromFileUrls: true,
            allowPopups: true,
            allowMixedContent: true,
            allowClipboardRead: true,
            allowClipboardWrite: true,
            allowGeolocation: true,
            allowCamera: true,
            allowMicrophone: true,
            allowProtectedMedia: true,
            enableContentIsolation: false,
            contentSecurityPolicy: "default-src 'self'",
          ),
          navigation: const PapyrusNavigationPolicy(
            defaultDecision: PapyrusNavigationDecision.openExternally,
            allowedSchemes: {'https', 'papyrus-resource'},
            externalSchemes: {'mailto', 'tel'},
            blockedSchemes: {'javascript'},
            requireUserGestureForExternalOpen: false,
            allowMainFrameNavigation: true,
            allowSubFrameNavigation: true,
          ),
          resources: PapyrusResourcePolicy(
            remoteResources: PapyrusRemoteResourceMode.allowByHost,
            allowedHosts: {'cdn.example.com'},
            allowedSchemes: {'https', 'papyrus-resource'},
            blockedResourceTypes: {PapyrusResourceType.image},
            virtualResourceOrigin: Uri.parse(
              'papyrus-resource://viewer.local/',
            ),
            enableRequestInterception: false,
          ),
          javascript: const PapyrusJavaScriptPolicy(
            mode: PapyrusJavaScriptMode.restricted,
            allowedChannels: {'bridge'},
            allowUserScripts: true,
            injectedScripts: [PapyrusUserScript('window.__papyrus = true;')],
          ),
          storage: const PapyrusStoragePolicy(
            cookies: PapyrusCookiePolicy.allowByHost,
            localStorage: PapyrusStorageMode.enabled,
            cache: PapyrusCacheMode.noCache,
            ephemeral: false,
            partitionId: 'viewer',
          ),
          media: const PapyrusMediaPolicy(
            autoPlay: true,
            inlinePlayback: true,
            requireUserGesture: false,
            allowFullscreen: true,
          ),
          display: const PapyrusDisplayPolicy(
            autoHeight: true,
            minimumHeight: 100,
            maximumHeight: 600,
            zoomEnabled: false,
            textZoom: 1.25,
            backgroundColor: 0xFF112233,
            darkMode: PapyrusDarkMode.dark,
            viewport: PapyrusViewportPolicy(width: '1024', scale: 1.5),
            measurement: PapyrusMeasurementPolicy(
              observeMutations: false,
              debounceMillis: 80,
            ),
          ),
          accessibility: const PapyrusAccessibilityPolicy(
            enableNativeSemantics: false,
          ),
          interaction: const PapyrusInteractionPolicy(
            allowTextSelection: false,
            allowContextMenu: false,
            allowLongPress: false,
          ),
          platform: const PapyrusPlatformOptions(
            debuggingEnabled: true,
            hardwareAcceleration: PapyrusHardwareAccelerationMode.software,
          ),
        ),
        resourceResolverEnabled: true,
      );

      expect(map['allowClipboardRead'], isTrue);
      expect(map['allowProtectedMedia'], isTrue);
      expect(map['navigationDefaultDecision'], 'openExternally');
      expect(map['navigationAllowedSchemes'], ['https', 'papyrus-resource']);
      expect(map['allowedJavaScriptChannels'], ['bridge']);
      expect(map['cookiePolicy'], 'allowByHost');
      expect(map['mediaAutoPlay'], isTrue);
      expect(map['backgroundColor'], 0xFF112233);
      expect(map['allowTextSelection'], isFalse);
      expect(map['allowContextMenu'], isFalse);
      expect(map['allowLongPress'], isFalse);
      expect(map['resourceResolverEnabled'], isTrue);
      expect(map['hardwareAcceleration'], 'software');
    });
  });

  group('policies', () {
    test('navigation policy blocks dangerous schemes first', () {
      const policy = PapyrusNavigationPolicy();

      expect(
        policy.resolve(
          PapyrusNavigationRequest(
            uri: Uri.parse('javascript:alert(1)'),
            isMainFrame: true,
            navigationType: PapyrusNavigationType.linkClicked,
            hasUserGesture: true,
          ),
        ),
        PapyrusNavigationDecision.block,
      );
    });

    test('resource policy supports host allowlists', () {
      const policy = PapyrusResourcePolicy(
        remoteResources: PapyrusRemoteResourceMode.allowByHost,
        allowedHosts: {'cdn.example.com'},
      );

      expect(policy.allows(Uri.parse('https://cdn.example.com/a.png')), isTrue);
      expect(
        policy.allows(Uri.parse('https://tracker.example/a.png')),
        isFalse,
      );
    });

    test('CSP injection is deterministic for fragments and documents', () {
      expect(
        PapyrusHtmlComposer.ensureDocument('<p>Hello</p>'),
        '<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><p>Hello</p></body></html>',
      );

      expect(
        PapyrusHtmlComposer.ensureDocument(
          '<html><head><meta name="viewport" content="width=320"></head><body><p>Hello</p></body></html>',
        ),
        '<html><head><meta name="viewport" content="width=320"></head><body><p>Hello</p></body></html>',
      );

      expect(
        PapyrusHtmlComposer.injectContentSecurityPolicy(
          '<p>Hello</p>',
          "default-src 'none'",
        ),
        '<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src \'none\'"><meta name="viewport" content="width=device-width, initial-scale=1"></head><body><p>Hello</p></body></html>',
      );

      expect(
        PapyrusHtmlComposer.injectContentSecurityPolicy(
          '<html><head><title>x</title></head><body></body></html>',
          'img-src https:',
        ),
        '<html><head><meta http-equiv="Content-Security-Policy" content="img-src https:"><meta name="viewport" content="width=device-width, initial-scale=1"><title>x</title></head><body></body></html>',
      );
    });

    test(
      'resource registry resolves providers in registration order',
      () async {
        final registry = PapyrusResourceRegistry()
          ..register(_NullProvider())
          ..register(_StaticProvider());

        final response = await registry.resolve(
          PapyrusResourceRequest(
            uri: Uri.parse('papyrus-resource://asset/logo.png'),
            method: 'GET',
            headers: const {},
            resourceType: PapyrusResourceType.image,
            isMainFrame: false,
          ),
        );

        expect(response?.mimeType, 'image/png');
        expect(response?.bytes, [1]);
      },
    );

    test('resource decision models represent allow, block, and response', () {
      final response = PapyrusResourceResponse(
        bytes: Uint8List.fromList([1, 2]),
        mimeType: 'text/css',
        headers: const {'cache-control': 'no-store'},
      );

      expect(const PapyrusAllowResource(), isA<PapyrusResourceDecision>());
      expect(const PapyrusBlockResource(), isA<PapyrusResourceDecision>());
      expect(
        PapyrusRespondWithResource(response).response.mimeType,
        'text/css',
      );
    });
  });

  group('platform interface', () {
    test('mock platform records load request and emits capabilities', () async {
      final platform = RecordingPapyrusPlatform();
      PapyrusPlatform.instance = platform;

      await PapyrusPlatform.instance.load(
        PapyrusUriRequest(uri: Uri.parse('https://example.com')),
      );

      expect(platform.loaded.single, isA<PapyrusUriRequest>());
      expect(
        await PapyrusPlatform.instance.getCapabilities(),
        const PapyrusPlatformCapabilities(
          supportsResourceInterception: true,
          supportsVirtualSchemes: true,
          supportsEphemeralStorage: true,
          supportsPrint: false,
          supportsSnapshot: false,
          supportsAutoHeight: false,
          supportsDarkMode: true,
          supportsDownloadInterception: true,
          supportsPermissionInterception: true,
        ),
      );
    });
  });
}

class _FakePapyrusPlatform extends PapyrusPlatform {}

class _NullProvider implements PapyrusVirtualResourceProvider {
  @override
  Future<PapyrusResourceResponse?> resolve(
    PapyrusResourceRequest request,
  ) async {
    return null;
  }
}

class _StaticProvider implements PapyrusVirtualResourceProvider {
  @override
  Future<PapyrusResourceResponse?> resolve(
    PapyrusResourceRequest request,
  ) async {
    return PapyrusResourceResponse(
      bytes: Uint8List.fromList([1]),
      mimeType: 'image/png',
    );
  }
}

class RecordingPapyrusPlatform extends PapyrusPlatform {
  final loaded = <PapyrusLoadRequest>[];

  @override
  Future<void> load(PapyrusLoadRequest request) async {
    request.validate();
    loaded.add(request);
  }

  @override
  Future<PapyrusPlatformCapabilities> getCapabilities() async {
    return const PapyrusPlatformCapabilities(
      supportsResourceInterception: true,
      supportsVirtualSchemes: true,
      supportsEphemeralStorage: true,
      supportsPrint: false,
      supportsSnapshot: false,
      supportsAutoHeight: false,
      supportsDarkMode: true,
      supportsDownloadInterception: true,
      supportsPermissionInterception: true,
    );
  }
}

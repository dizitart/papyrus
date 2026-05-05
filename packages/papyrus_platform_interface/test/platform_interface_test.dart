import 'dart:typed_data';

import 'package:papyrus_platform_interface/papyrus_platform_interface.dart';
import 'package:test/test.dart';

void main() {
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
            '<!doctype html><html><head></head><body><p>Hello</p></body></html>',
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
        '<!doctype html><html><head></head><body><p>Hello</p></body></html>',
      );

      expect(
        PapyrusHtmlComposer.injectContentSecurityPolicy(
          '<p>Hello</p>',
          "default-src 'none'",
        ),
        '<!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src \'none\'"></head><body><p>Hello</p></body></html>',
      );

      expect(
        PapyrusHtmlComposer.injectContentSecurityPolicy(
          '<html><head><title>x</title></head><body></body></html>',
          'img-src https:',
        ),
        '<html><head><meta http-equiv="Content-Security-Policy" content="img-src https:"><title>x</title></head><body></body></html>',
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

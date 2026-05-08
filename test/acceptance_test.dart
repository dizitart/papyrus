import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('federated package tree and documentation are present', () {
    for (final path in [
      'packages/papyrus/pubspec.yaml',
      'packages/papyrus_platform_interface/pubspec.yaml',
      'packages/papyrus_android/pubspec.yaml',
      'packages/papyrus_ios/pubspec.yaml',
      'packages/papyrus_macos/pubspec.yaml',
      'packages/papyrus_windows/pubspec.yaml',
      'packages/papyrus_linux/pubspec.yaml',
      'examples/papyrus_example/pubspec.yaml',
      'docs/security.md',
      'docs/email_html_usage.md',
      'docs/platform_matrix.md',
      'test/golden/baselines.json',
      'examples/papyrus_example/integration_test/papyrus_native_smoke_test.dart',
      'packages/papyrus_android/android/src/main/kotlin/dev/papyrus/papyrus_android/PapyrusAndroidPlugin.kt',
      'packages/papyrus_ios/ios/Classes/PapyrusIosPlugin.swift',
      'packages/papyrus_macos/macos/Classes/PapyrusMacosPlugin.swift',
      'packages/papyrus_windows/windows/papyrus_windows_plugin.cpp',
      'packages/papyrus_linux/linux/papyrus_linux_plugin.cc',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('conformance manifest includes controlled-content scenarios', () {
    final manifest =
        jsonDecode(File('test/conformance/fixtures.json').readAsStringSync())
            as Map<String, Object?>;
    final fixtures = manifest['fixtures']! as List<Object?>;
    final ids = fixtures
        .cast<Map<String, Object?>>()
        .map((fixture) => fixture['id'])
        .toSet();

    expect(ids, contains('table-heavy-html'));
    expect(ids, contains('blocked-tracking-pixel'));
    expect(ids, contains('virtual-image'));
    expect(ids, contains('rtl-cjk-emoji'));
    expect(ids, contains('malformed-browser-recoverable'));
  });

  test('docs preserve non-goals and native-engine positioning', () {
    final security = File('docs/security.md').readAsStringSync();
    final email = File('docs/email_html_usage.md').readAsStringSync();
    final architecture = File('docs/architecture.md').readAsStringSync();

    expect(security, contains('does not sanitize'));
    expect(email, contains('MIME parsing'));
    expect(architecture, contains('Android System WebView'));
    expect(architecture, contains('WKWebView'));
    expect(architecture, contains('WebView2'));
    expect(architecture, contains('WebKitGTK'));
  });

  test('native plugin code exposes Papyrus channels and engine hooks', () {
    final android = File(
      'packages/papyrus_android/android/src/main/kotlin/dev/papyrus/papyrus_android/PapyrusAndroidPlugin.kt',
    ).readAsStringSync();
    final ios = File(
      'packages/papyrus_ios/ios/Classes/PapyrusIosPlugin.swift',
    ).readAsStringSync();
    final macos = File(
      'packages/papyrus_macos/macos/Classes/PapyrusMacosPlugin.swift',
    ).readAsStringSync();
    final windows = File(
      'packages/papyrus_windows/windows/papyrus_windows_plugin.cpp',
    ).readAsStringSync();
    final linux = File(
      'packages/papyrus_linux/linux/papyrus_linux_plugin.cc',
    ).readAsStringSync();

    expect(android, contains('WebView'));
    expect(android, contains('dev.papyrus.papyrus_android'));
    expect(android, contains('shouldOverrideUrlLoading'));
    expect(ios, contains('WKWebView'));
    expect(ios, contains('dev.papyrus.papyrus_ios'));
    expect(macos, contains('WKWebView'));
    expect(macos, contains('dev.papyrus.papyrus_macos'));
    expect(windows, contains('dev.papyrus.papyrus_windows'));
    expect(windows, contains('CreateCoreWebView2EnvironmentWithOptions'));
    expect(windows, contains('getCapabilities'));
    expect(linux, contains('dev.papyrus.papyrus_linux'));
    expect(linux, contains('webkit_web_view_load_html'));
    expect(linux, contains('gtk_overlay_add_overlay'));
    expect(linux, contains('getCapabilities'));
  });

  test('linux examples install debug bundles into the build directory', () {
    for (final path in [
      'examples/papyrus_example/linux/CMakeLists.txt',
      'examples/papyrus_testbed/linux/CMakeLists.txt',
    ]) {
      final cmake = File(path).readAsStringSync();

      expect(cmake, contains('set(BUILD_BUNDLE_DIR "\${PROJECT_BINARY_DIR}/bundle")'));
      expect(
        cmake,
        contains(
          'CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT OR CMAKE_INSTALL_PREFIX STREQUAL "/usr/local"',
        ),
        reason: path,
      );
      expect(
        cmake,
        contains('set(CMAKE_INSTALL_PREFIX "\${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)'),
        reason: path,
      );
    }
  });

  test('integration smoke tests cover native load and capability contracts', () {
    final smoke = File(
      'examples/papyrus_example/integration_test/papyrus_native_smoke_test.dart',
    ).readAsStringSync();

    expect(smoke, contains('loadHtmlString'));
    expect(smoke, contains('getCapabilities'));
    expect(smoke, contains('PapyrusProfiles.lockedDown'));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus_macos/papyrus_macos.dart';

void main() {
  test('macOS prefers the desktop overlay by default', () {
    final platform = PapyrusMacos();

    expect(platform.supportsOverlaySurface, isTrue);
    expect(platform.supportsNativeView, isFalse);
  });
}

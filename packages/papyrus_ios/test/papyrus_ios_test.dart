import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus_ios/papyrus_ios.dart';

void main() {
  test('iOS uses the native platform view path', () {
    final platform = PapyrusIos();

    expect(platform.supportsNativeView, isTrue);
    expect(platform.supportsOverlaySurface, isFalse);
  });
}

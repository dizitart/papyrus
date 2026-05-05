import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus_linux/papyrus_linux.dart';

void main() {
  test('Linux uses the desktop overlay path', () {
    final platform = PapyrusLinux();

    expect(platform.supportsOverlaySurface, isTrue);
    expect(platform.supportsNativeView, isFalse);
  });
}

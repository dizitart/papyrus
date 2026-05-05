import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus_windows/papyrus_windows.dart';

void main() {
  test('Windows uses the desktop overlay path', () {
    final platform = PapyrusWindows();

    expect(platform.supportsOverlaySurface, isTrue);
    expect(platform.supportsNativeView, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus_android/papyrus_android.dart';

void main() {
  test('Android uses the native platform view path', () {
    final platform = PapyrusAndroid();

    expect(platform.supportsNativeView, isTrue);
    expect(platform.supportsOverlaySurface, isFalse);
  });
}

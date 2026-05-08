import 'package:flutter_test/flutter_test.dart';
import 'package:papyrus/papyrus.dart';

import 'package:papyrus_testbed/main.dart';

void main() {
  setUp(() {
    PapyrusPlatform.instance = _TestPapyrusPlatform();
  });

  testWidgets('Papyrus testbed app renders main tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PapyrusTestbedApp());
    await tester.pumpAndSettle();

    expect(find.text('Papyrus Testbed'), findsOneWidget);
    expect(find.text('Raw HTML + CSS'), findsOneWidget);
    expect(find.text('Raw MIME Email'), findsOneWidget);
  });
}

class _TestPapyrusPlatform extends PapyrusPlatform {
  @override
  Future<void> load(PapyrusLoadRequest request) async {
    request.validate();
  }

  @override
  Future<PapyrusPlatformCapabilities> getCapabilities() async {
    return const PapyrusPlatformCapabilities(
      supportsResourceInterception: false,
      supportsVirtualSchemes: false,
      supportsEphemeralStorage: false,
      supportsPrint: false,
      supportsSnapshot: false,
      supportsAutoHeight: true,
      supportsDarkMode: false,
      supportsDownloadInterception: false,
      supportsPermissionInterception: false,
    );
  }
}

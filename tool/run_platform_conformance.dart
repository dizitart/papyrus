import 'dart:io';

final class _RunnerOptions {
  const _RunnerOptions({
    required this.device,
    required this.runChecks,
    required this.runSmoke,
    required this.runApi,
    required this.useNativeMacosPlatformView,
  });

  final String device;
  final bool runChecks;
  final bool runSmoke;
  final bool runApi;
  final bool useNativeMacosPlatformView;
}

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _printUsage();
    return;
  }

  final options = _parseArgs(arguments);
  if (!options.runChecks && !options.runSmoke && !options.runApi) {
    stderr.writeln('Nothing to run. Remove one of the --skip-* flags.');
    exitCode = 64;
    return;
  }

  final rootDir = _repositoryRoot();

  if (options.runChecks) {
    await _runFlutter(rootDir, 'packages/papyrus_platform_interface', ['test']);
    await _runFlutter(rootDir, 'packages/papyrus_platform_interface', [
      'analyze',
    ]);
    await _runFlutter(rootDir, 'packages/papyrus', ['test']);
    await _runFlutter(rootDir, 'packages/papyrus', ['analyze']);

    for (final package in const [
      'packages/papyrus_android',
      'packages/papyrus_ios',
      'packages/papyrus_macos',
      'packages/papyrus_windows',
      'packages/papyrus_linux',
    ]) {
      await _runFlutter(rootDir, package, ['analyze']);
    }

    await _runFlutter(rootDir, '.', ['test', 'test/acceptance_test.dart']);
  }

  final integrationEnvironment = <String, String>{...Platform.environment};
  if (options.useNativeMacosPlatformView) {
    integrationEnvironment['PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW'] = 'true';
  }

  if (options.runSmoke) {
    await _runFlutter(rootDir, 'examples/papyrus_example', [
      'test',
      'integration_test/papyrus_native_smoke_test.dart',
      '-d',
      options.device,
    ], environment: integrationEnvironment);
  }

  if (options.runApi) {
    await _runFlutter(rootDir, 'examples/papyrus_example', [
      'test',
      'integration_test/papyrus_public_api_conformance_test.dart',
      '-d',
      options.device,
    ], environment: integrationEnvironment);
  }
}

_RunnerOptions _parseArgs(List<String> arguments) {
  String? device;
  var runChecks = true;
  var runSmoke = true;
  var runApi = true;
  var useNativeMacosPlatformView = false;

  for (var index = 0; index < arguments.length; index += 1) {
    final argument = arguments[index];
    switch (argument) {
      case '--device':
      case '-d':
        if (index + 1 >= arguments.length) {
          stderr.writeln('Missing value for $argument.');
          _printUsage();
          exit(64);
        }
        device = arguments[index + 1];
        index += 1;
      case '--skip-checks':
        runChecks = false;
      case '--skip-smoke':
        runSmoke = false;
      case '--skip-api':
        runApi = false;
      case '--native-macos-platform-view':
        useNativeMacosPlatformView = true;
      default:
        stderr.writeln('Unknown argument: $argument');
        _printUsage();
        exit(64);
    }
  }

  if (device == null || device.isEmpty) {
    stderr.writeln('A Flutter device id is required.');
    _printUsage();
    exit(64);
  }

  return _RunnerOptions(
    device: device,
    runChecks: runChecks,
    runSmoke: runSmoke,
    runApi: runApi,
    useNativeMacosPlatformView: useNativeMacosPlatformView,
  );
}

String _repositoryRoot() {
  return File.fromUri(Platform.script).parent.parent.path;
}

Future<void> _runFlutter(
  String rootDir,
  String relativeDirectory,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final workingDirectory = relativeDirectory == '.'
      ? rootDir
      : '$rootDir${Platform.pathSeparator}$relativeDirectory';
  stdout.writeln('==> ($relativeDirectory) flutter ${arguments.join(' ')}');

  final process = await Process.start(
    'flutter',
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
    environment: environment,
  );

  final code = await process.exitCode;
  if (code != 0) {
    exit(code);
  }
}

void _printUsage() {
  stdout.writeln('''
Usage: dart run tool/run_platform_conformance.dart --device <flutter-device-id> [options]

Runs the repository contract checks and the device-backed Papyrus integration suites.

Options:
  -d, --device <id>              Flutter device id or desktop target such as macos, linux, or windows.
      --skip-checks              Skip the package tests/analyze and root acceptance test.
      --skip-smoke               Skip integration_test/papyrus_native_smoke_test.dart.
      --skip-api                 Skip integration_test/papyrus_public_api_conformance_test.dart.
      --native-macos-platform-view
                                 Set PAPYRUS_USE_NATIVE_MACOS_PLATFORM_VIEW=true for macOS runs.
  -h, --help                     Show this help.

Examples:
  dart run tool/run_platform_conformance.dart --device macos
  dart run tool/run_platform_conformance.dart --device macos --native-macos-platform-view
  dart run tool/run_platform_conformance.dart --device emulator-5554 --skip-checks
  dart run tool/run_platform_conformance.dart --device 4BC64162-0CFF-4C35-B60E-7B4A4EFF0770 --skip-checks
  dart run tool/run_platform_conformance.dart --device linux --skip-checks
  dart run tool/run_platform_conformance.dart --device windows --skip-checks
''');
}

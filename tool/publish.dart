#!/usr/bin/env dart
// ignore_for_file: avoid_print
//
// tool/publish.dart
//
// Publishes all papyrus packages to pub.dev in correct dependency order.
//
// Usage:
//   dart run tool/publish.dart            # publish all packages
//   dart run tool/publish.dart --dry-run  # validate only, no actual publish
//
// Prerequisites:
//   • Run from the repository root.
//   • Authenticate first: `dart pub login` (or use OIDC in GitHub Actions).
//   • All packages must be at the same version for coordinated releases.
//
// Publish order (dependency graph bottom-up):
//   1. papyrus_platform_interface   — no intra-repo deps
//   2. papyrus_android              — depends on platform_interface
//   3. papyrus_ios                  — depends on platform_interface
//   4. papyrus_macos                — depends on platform_interface
//   5. papyrus_windows              — depends on platform_interface
//   6. papyrus_linux                — depends on platform_interface
//   7. papyrus                      — depends on all of the above

import 'dart:io';
import 'dart:async';

/// Packages in publish order (dependency graph bottom-up).
const _packages = <String>[
  'packages/papyrus_platform_interface',
  'packages/papyrus_android',
  'packages/papyrus_ios',
  'packages/papyrus_macos',
  'packages/papyrus_windows',
  'packages/papyrus_linux',
  'packages/papyrus',
];

/// How long to wait between publishes for pub.dev index propagation.
const _propagationDelay = Duration(seconds: 60);

/// Hard timeout for each `pub publish` invocation.
const _publishTimeout = Duration(minutes: 15);

/// Periodic keepalive log while a publish command is running.
const _publishHeartbeat = Duration(seconds: 30);

/// Regex that matches a two-line path dependency block and replaces it with
/// a single inline version constraint. Pattern matches:
/// ```yaml
///   papyrus_foo:
///     path: ../papyrus_foo
/// ```
final _pathDepPattern = RegExp(r'  (papyrus_[a-z_]+):\n    path: \.\./\1');

void main(List<String> args) async {
  final dryRun = args.contains('--dry-run');

  if (dryRun) {
    _log('Running in DRY-RUN mode — no packages will be published.');
  }

  // Validate we are at the repository root.
  if (!File('pubspec.yaml').existsSync() ||
      !Directory('packages').existsSync()) {
    _die('Must be run from the repository root.');
  }

  // Read the coordinated release version from the platform-interface package
  // (the foundational package that all others depend on).
  final version = _readVersion('packages/papyrus_platform_interface');
  _log('Publishing version: $version');

  final failed = <String>[];

  for (var i = 0; i < _packages.length; i++) {
    final pkgDir = _packages[i];
    final pkgName = pkgDir.split('/').last;
    _log('\n[${i + 1}/${_packages.length}] Publishing $pkgName ...');

    final pubspecFile = File('$pkgDir/pubspec.yaml');
    final packageLicenseFile = File('$pkgDir/LICENSE');
    final originalContent = pubspecFile.readAsStringSync();
    var addedTemporaryLicense = false;

    // pub.dev validation requires each package directory to contain LICENSE.
    // Mirror the repository root license into package roots when missing.
    if (!packageLicenseFile.existsSync()) {
      final rootLicenseFile = File('LICENSE');
      if (!rootLicenseFile.existsSync()) {
        _die('Repository root LICENSE file is missing.');
      }
      packageLicenseFile.writeAsStringSync(rootLicenseFile.readAsStringSync());
      addedTemporaryLicense = true;
      _log('  Added temporary LICENSE');
    }

    // Replace path: dependencies with version constraints before publishing.
    final patchedContent = _replacePaths(originalContent, version);
    final didPatch = patchedContent != originalContent;

    if (didPatch) {
      _log('  Patching path: dependencies → ^$version');
      pubspecFile.writeAsStringSync(patchedContent);
    }

    try {
      final ok = await _publish(pkgDir, dryRun: dryRun);
      if (!ok) {
        failed.add(pkgName);
        _log('  ERROR: publish failed for $pkgName');
      }
    } finally {
      // Always restore the original pubspec.yaml.
      if (didPatch) {
        pubspecFile.writeAsStringSync(originalContent);
        _log('  Restored original pubspec.yaml');
      }
      if (addedTemporaryLicense && packageLicenseFile.existsSync()) {
        packageLicenseFile.deleteSync();
        _log('  Removed temporary LICENSE');
      }
    }

    // Wait for pub.dev to index the package before publishing dependents,
    // but skip the delay after the last package or in dry-run mode.
    final isLast = i == _packages.length - 1;
    if (!dryRun && !isLast && failed.isEmpty) {
      _log(
        '  Waiting ${_propagationDelay.inSeconds}s for pub.dev propagation...',
      );
      await Future<void>.delayed(_propagationDelay);
    }
  }

  if (failed.isNotEmpty) {
    _die('The following packages failed to publish: ${failed.join(', ')}');
  }

  _log('\nAll packages published successfully.');
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Reads the `version:` field from a package's pubspec.yaml.
String _readVersion(String pkgDir) {
  final content = File('$pkgDir/pubspec.yaml').readAsStringSync();
  final match = RegExp(
    r'^version:\s+(\S+)',
    multiLine: true,
  ).firstMatch(content);
  if (match == null) _die('Could not read version from $pkgDir/pubspec.yaml');
  return match.group(1)!;
}

/// Replaces two-line path: dependency blocks with inline version constraints.
///
/// Input (two lines):
/// ```
///   papyrus_platform_interface:
///     path: ../papyrus_platform_interface
/// ```
/// Output (one line):
/// ```
///   papyrus_platform_interface: ^0.1.0
/// ```
String _replacePaths(String content, String version) {
  return content.replaceAllMapped(_pathDepPattern, (m) {
    return '  ${m.group(1)!}: ^$version';
  });
}

/// Runs `dart pub publish` (or `flutter pub publish` for Flutter packages)
/// in [pkgDir]. Returns true on success.
Future<bool> _publish(String pkgDir, {required bool dryRun}) async {
  // Determine whether the package uses Flutter (has flutter sdk dep).
  final pubspecContent = File('$pkgDir/pubspec.yaml').readAsStringSync();
  final isFlutter = pubspecContent.contains('sdk: flutter');

  final executable = isFlutter ? 'flutter' : 'dart';
  final publishArgs = <String>['pub', 'publish'];

  if (dryRun) {
    publishArgs.add('--dry-run');
    publishArgs.add('--skip-validation');
  } else {
    publishArgs.add('--force');
  }

  _log('  Running: $executable ${publishArgs.join(' ')}');

  final process = await Process.start(
    executable,
    publishArgs,
    workingDirectory: pkgDir,
    runInShell: true,
  );

  final startedAt = DateTime.now();
  final heartbeat = Timer.periodic(_publishHeartbeat, (_) {
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    _log('  Still publishing... (${elapsed}s elapsed)');
  });

  final stdoutDone = stdout.addStream(process.stdout);
  final stderrDone = stderr.addStream(process.stderr);

  final exitCode = await process.exitCode.timeout(
    _publishTimeout,
    onTimeout: () {
      _log(
        '  ERROR: publish command timed out after '
        '${_publishTimeout.inMinutes} minutes; terminating process.',
      );
      process.kill(ProcessSignal.sigterm);
      return -1;
    },
  );

  heartbeat.cancel();
  await stdoutDone;
  await stderrDone;

  if (exitCode == -1 && process.kill(ProcessSignal.sigkill)) {
    _log('  Force-killed timed out publish process.');
  }

  return exitCode == 0;
}

void _log(String message) => print(message);

Never _die(String message) {
  stderr.writeln('FATAL: $message');
  exit(1);
}

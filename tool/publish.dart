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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

/// How often to poll pub.dev while waiting for a dependency to become
/// resolvable.
const _propagationPollInterval = Duration(seconds: 15);

/// Max time to wait for a just-published dependency to propagate, matching
/// pub.dev's own "may take up-to 10 minutes" upload message.
const _propagationTimeout = Duration(minutes: 10);

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

    if (!dryRun && await _isVersionPublished(pkgName, version)) {
      _log('  Version $version already exists on pub.dev — skipping.');
      continue;
    }

    final pubspecFile = File('$pkgDir/pubspec.yaml');
    final originalContent = pubspecFile.readAsStringSync();

    // Wait for this package's intra-repo dependencies to actually be
    // resolvable on pub.dev before attempting to publish against them —
    // a fixed delay undershoots pub.dev's own "may take up-to 10 minutes"
    // propagation window.
    if (!dryRun) {
      for (final depName
          in _pathDepPattern
              .allMatches(originalContent)
              .map((m) => m.group(1)!)) {
        await _waitUntilPublished(depName, version);
      }
    }

    final patchedContent = _replacePaths(originalContent, version);
    final didPatch = patchedContent != originalContent;

    final publishDir = await _preparePublishDirectory(
      pkgDir,
      patchedPubspec: patchedContent,
      didPatchPubspec: didPatch,
    );

    if (didPatch) {
      _log('  Patching path: dependencies → ^$version in publish copy');
    }

    try {
      final ok = await _publishWithRetry(publishDir.path, dryRun: dryRun);
      if (!ok) {
        failed.add(pkgName);
        _log('  ERROR: publish failed for $pkgName');
      }
    } finally {
      await publishDir.parent.delete(recursive: true);
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

/// Polls pub.dev until [packageName] resolves at [version], so a dependent
/// package's `pub publish` doesn't hit a stale index.
Future<void> _waitUntilPublished(String packageName, String version) async {
  final deadline = DateTime.now().add(_propagationTimeout);
  var logged = false;
  while (!await _isVersionPublished(packageName, version)) {
    if (DateTime.now().isAfter(deadline)) {
      _log(
        '  WARNING: $packageName $version not visible on pub.dev after '
        '${_propagationTimeout.inMinutes}m; proceeding anyway.',
      );
      return;
    }
    if (!logged) {
      _log(
        '  Waiting for $packageName $version to propagate on pub.dev '
        '(polling every ${_propagationPollInterval.inSeconds}s)...',
      );
      logged = true;
    }
    await Future<void>.delayed(_propagationPollInterval);
  }
}

/// Returns true when [packageName] already has [version] on pub.dev.
///
/// This makes rerunning a release tag idempotent and avoids invoking
/// `pub publish` for versions that can no longer be uploaded.
Future<bool> _isVersionPublished(String packageName, String version) async {
  final client = HttpClient();
  try {
    final uri = Uri.https('pub.dev', '/api/packages/$packageName');
    final request = await client.getUrl(uri);
    final response = await request.close();

    if (response.statusCode == HttpStatus.notFound) {
      return false;
    }

    if (response.statusCode != HttpStatus.ok) {
      _log(
        '  Could not check existing versions on pub.dev '
        '(HTTP ${response.statusCode}); continuing.',
      );
      return false;
    }

    final body = await utf8.decoder.bind(response).join();
    final packageInfo = jsonDecode(body) as Map<String, Object?>;
    final versions = packageInfo['versions'];
    if (versions is! List) {
      return false;
    }

    return versions.any((entry) {
      if (entry is! Map) return false;
      return entry['version'] == version;
    });
  } on Object catch (error) {
    _log('  Could not check existing versions on pub.dev: $error');
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Copies [pkgDir] to a temporary directory and applies publish-only changes.
///
/// Publishing from a copy keeps the checked-out release tag clean while still
/// replacing intra-repo path dependencies with hosted version constraints.
Future<Directory> _preparePublishDirectory(
  String pkgDir, {
  required String patchedPubspec,
  required bool didPatchPubspec,
}) async {
  final tempRoot = await Directory.systemTemp.createTemp('papyrus_publish_');
  final publishDir = Directory('${tempRoot.path}/${pkgDir.split('/').last}');
  await _copyTrackedPackageFiles(pkgDir, publishDir);

  if (didPatchPubspec) {
    await File('${publishDir.path}/pubspec.yaml').writeAsString(patchedPubspec);
  }

  final packageLicenseFile = File('${publishDir.path}/LICENSE');
  if (!packageLicenseFile.existsSync()) {
    final rootLicenseFile = File('LICENSE');
    if (!rootLicenseFile.existsSync()) {
      _die('Repository root LICENSE file is missing.');
    }
    await packageLicenseFile.writeAsString(
      await rootLicenseFile.readAsString(),
    );
    _log('  Added LICENSE to publish copy');
  }

  return publishDir;
}

Future<void> _copyTrackedPackageFiles(
  String pkgDir,
  Directory destination,
) async {
  await destination.create(recursive: true);

  final result = await Process.run('git', ['ls-files', '--', pkgDir]);
  if (result.exitCode != 0) {
    _die('Could not list tracked files for $pkgDir: ${result.stderr}');
  }

  final packagePrefix = '$pkgDir/';
  final trackedFiles = LineSplitter.split(
    result.stdout as String,
  ).where((path) => path.startsWith(packagePrefix));

  for (final sourcePath in trackedFiles) {
    final relativePath = sourcePath.substring(packagePrefix.length);
    final target = File('${destination.path}/$relativePath');
    await target.parent.create(recursive: true);
    await File(sourcePath).copy(target.path);
  }
}

/// Outcome of a single `pub publish` attempt.
///
/// [retryable] is true when the failure looks like a pub.dev index
/// propagation lag (an intra-repo dependency just published moments ago
/// isn't resolvable yet) rather than a real validation error.
typedef _PublishResult = ({bool ok, bool retryable});

/// Runs `dart pub publish` (or `flutter pub publish` for Flutter packages)
/// in [pkgDir], retrying while the failure looks like pub.dev index
/// propagation lag. Returns true on eventual success.
Future<bool> _publishWithRetry(String pkgDir, {required bool dryRun}) async {
  final deadline = DateTime.now().add(_propagationTimeout);
  while (true) {
    final result = await _publish(pkgDir, dryRun: dryRun);
    if (result.ok || !result.retryable || DateTime.now().isAfter(deadline)) {
      return result.ok;
    }
    _log(
      '  Dependency not yet resolvable on pub.dev; retrying in '
      '${_propagationPollInterval.inSeconds}s...',
    );
    await Future<void>.delayed(_propagationPollInterval);
  }
}

/// Runs a single `dart pub publish` (or `flutter pub publish` for Flutter
/// packages) invocation in [pkgDir].
Future<_PublishResult> _publish(String pkgDir, {required bool dryRun}) async {
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

  // Capture output so we can detect already-published responses.
  final outputBuffer = StringBuffer();
  final stdoutLines = process.stdout
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter());
  final stderrLines = process.stderr
      .transform(const SystemEncoding().decoder)
      .transform(const LineSplitter());

  final stdoutDone = stdoutLines.listen((line) {
    stdout.writeln(line);
    outputBuffer.writeln(line);
  }).asFuture<void>();
  final stderrDone = stderrLines.listen((line) {
    stderr.writeln(line);
    outputBuffer.writeln(line);
  }).asFuture<void>();

  var timedOut = false;
  Timer? forceKillTimer;
  final timeoutTimer = Timer(_publishTimeout, () {
    timedOut = true;
    _log(
      '  ERROR: publish command timed out after '
      '${_publishTimeout.inMinutes} minutes; terminating process.',
    );
    process.kill(ProcessSignal.sigterm);
    forceKillTimer = Timer(const Duration(seconds: 5), () {
      if (process.kill(ProcessSignal.sigkill)) {
        _log('  Force-killed timed out publish process.');
      }
    });
  });

  final exitCode = await process.exitCode;
  timeoutTimer.cancel();
  forceKillTimer?.cancel();
  heartbeat.cancel();

  await stdoutDone;
  await stderrDone;

  if (timedOut) {
    // A publish command that exceeded our timeout is treated as failed even
    // if it eventually exits zero after being signaled.
    return (ok: false, retryable: false);
  }

  if (exitCode != 0) {
    final output = outputBuffer.toString().toLowerCase();
    // Treat already-published versions as success so re-runs are safe.
    if (output.contains('already published') ||
        output.contains('already exists')) {
      _log('  Already published — skipping.');
      return (ok: true, retryable: false);
    }
    // A dependency published moments ago that isn't resolvable yet is a
    // pub.dev index propagation lag, not a real validation failure.
    final retryable =
        output.contains('version solving failed') ||
        output.contains("doesn't match any versions");
    return (ok: false, retryable: retryable);
  }

  return (ok: true, retryable: false);
}

void _log(String message) => print(message);

Never _die(String message) {
  stderr.writeln('ERROR: $message');
  exit(1);
}

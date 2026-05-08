# Release Workflow

This document is the production release runbook for publishing Papyrus packages
to pub.dev from GitHub Actions.

## Scope

Papyrus is a federated monorepo that publishes these packages together:

- `papyrus_platform_interface`
- `papyrus_android`
- `papyrus_ios`
- `papyrus_macos`
- `papyrus_windows`
- `papyrus_linux`
- `papyrus`

All seven packages should be released at the same version.

## Workflows

- CI: `.github/workflows/ci.yml`
- Publish: `.github/workflows/publish.yml`
- Publisher script: `tool/publish.dart`

## CI gates (must pass before tagging)

`ci.yml` runs the following checks:

- Format check (`dart format --set-exit-if-changed`) for each package
- Static analysis (`flutter analyze --fatal-infos`) for each package
- Package tests for each package (when test files exist)
- Workspace acceptance test (`test/acceptance_test.dart`)
- Publish dry-run validation (`dart run tool/publish.dart --dry-run`)
- Windows native tests (CMake + ctest)

## One-time pub.dev setup (OIDC automated publishing)

Do this once per package on pub.dev:

1. Ensure package exists on pub.dev (first publish can be manual).
2. Open `https://pub.dev/packages/<package>/admin`.
3. Add **Automated publishing** with:
   - Repository: `dizitart/papyrus`
   - Workflow: `publish.yml`
   - Tag pattern: `v{{version}}`

`publish.yml` already requests `id-token: write`, which pub.dev uses for OIDC.
No long-lived `PUB_TOKEN` secret is required after setup.

## Release checklist

1. Update `version:` in all seven package `pubspec.yaml` files.
2. Update all seven package `CHANGELOG.md` files.
3. Run checks locally:
   - `flutter test test/acceptance_test.dart`
   - `dart run tool/publish.dart --dry-run`
4. Commit changes.
5. Create and push a release tag:
   - `git tag v<semver>`
   - `git push origin main v<semver>`

## Publish behavior

The publish workflow runs only on tags matching `vX.Y.Z`.

`tool/publish.dart` publishes packages in dependency order:

1. `papyrus_platform_interface`
2. `papyrus_android`
3. `papyrus_ios`
4. `papyrus_macos`
5. `papyrus_windows`
6. `papyrus_linux`
7. `papyrus`

For each package, it:

- Temporarily rewrites local `path:` dependencies to `^<version>` constraints
- Runs `dart pub publish --force` or `flutter pub publish --force`
- Restores the original `pubspec.yaml`
- Waits 60 seconds between packages for pub.dev index propagation

## Rollback / failed publish notes

- If a package publish fails, fix the issue and release a new patch version.
- Never attempt to republish an already published version.
- Keep versions synchronized across all seven packages.

# Production Release Pipeline

Android Dev Agent ships through a Developer ID direct-distribution pipeline with Sparkle updates. The pipeline is intentionally split into package, verify, promote, and rollback phases so a release candidate can be inspected before the public appcast changes.

## Pipeline Phases

1. CI builds and tests the Swift package.
2. `scripts/package_macos_app.sh` creates the signed app bundle, signed installer package, Sparkle zip archive, release notes, appcast, and release manifest.
3. `scripts/verify_release_artifacts.sh` verifies bundle metadata, Developer ID signatures, package signature, zip contents, Sparkle appcast signatures, and notarization staples when required.
4. `scripts/promote_release.sh` stages the appcast tree, snapshots the previous published channel, promotes the new appcast and archives, and optionally syncs the promoted tree to the hosted update server.
5. `scripts/rollback_release.sh` restores the prior channel snapshot and optionally syncs it back to the hosted update server.

## Required Production Secrets

Store these in the CI secret store, not in the repository:

```text
MACOS_CERTIFICATE_P12_BASE64
MACOS_CERTIFICATE_PASSWORD
MACOS_INSTALLER_CERTIFICATE_P12_BASE64
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
SPARKLE_PUBLIC_ED_KEY
SPARKLE_PRIVATE_KEY
APPCAST_SSH_PRIVATE_KEY
APPCAST_RSYNC_TARGET
```

Use CI variables for non-secret release configuration:

```text
BUNDLE_ID
DEVELOPER_ID_APPLICATION
DEVELOPER_ID_INSTALLER
UPDATE_BASE_URL
LICENSE_ACTIVATION_URL
LICENSE_REFRESH_URL
LICENSE_RECOVERY_URL
LICENSE_TRANSFER_URL
PRIVACY_POLICY_URL
CRASH_REPORTING_ENDPOINT
SUPPORT_UPLOAD_ENDPOINT
SYMBOL_UPLOAD_ENDPOINT
```

## Local Release Candidate

```bash
RELEASE=1 \
BUNDLE_ID=com.yourcompany.androiddevagent \
SIGNING_IDENTITY="Developer ID Application: Your Company (TEAMID)" \
INSTALLER_SIGNING_IDENTITY="Developer ID Installer: Your Company (TEAMID)" \
SPARKLE_PUBLIC_ED_KEY="base64-public-ed25519-key" \
UPDATE_BASE_URL=https://updates.yourcompany.com/android-dev-agent/stable \
NOTARYTOOL_PROFILE=android-dev-agent \
LICENSE_ACTIVATION_URL=https://api.yourcompany.com/android-dev-agent/license/activate \
LICENSE_REFRESH_URL=https://api.yourcompany.com/android-dev-agent/license/refresh \
LICENSE_RECOVERY_URL=https://api.yourcompany.com/android-dev-agent/license/recover \
LICENSE_TRANSFER_URL=https://api.yourcompany.com/android-dev-agent/license/transfer \
LICENSE_POLICY_PATH=docs/release-evidence/license-policy.md \
PRIVACY_POLICY_URL=https://yourcompany.com/privacy/android-dev-agent \
DATA_RETENTION_POLICY_PATH=docs/release-evidence/data-retention-policy.md \
SUPPORT_REDACTION_POLICY_PATH=docs/release-evidence/support-redaction-policy.md \
CRASH_REPORTING_ENDPOINT=https://crash.yourcompany.com/android-dev-agent \
SUPPORT_UPLOAD_ENDPOINT=https://support.yourcompany.com/android-dev-agent/bundles \
SYMBOL_UPLOAD_ENDPOINT=https://support.yourcompany.com/android-dev-agent/symbols \
CRASH_PIPELINE_RUNBOOK_PATH=docs/release-evidence/crash-pipeline-runbook.md \
SPARKLE_ROLLOUT_PLAN_PATH=docs/release-evidence/sparkle-rollout-plan.md \
SPARKLE_ROLLBACK_PLAN_PATH=docs/release-evidence/sparkle-rollback-plan.md \
ANDROID_MATRIX_REPORT_PATH=docs/release-evidence/android-matrix-report.md \
bash scripts/package_macos_app.sh
```

The package script writes:

```text
dist/release/<channel>/<version>-<build>/release-manifest.json
dist/release/<channel>/<version>-<build>/artifact-verification.json
dist/updates/<channel>/appcast.xml
dist/updates/<channel>/AndroidDevAgent-<version>-<build>-<channel>.zip
```

## Promotion

Promote only after the release manifest and artifact verification report are reviewed:

```bash
PROMOTE_RELEASE=1 \
APPCAST_HOSTING_DIR=/srv/www/updates/android-dev-agent \
APPCAST_RSYNC_TARGET=deploy@updates.yourcompany.com:/srv/www/updates/android-dev-agent/stable \
RELEASE=1 \
bash scripts/package_macos_app.sh
```

To promote an already packaged candidate:

```bash
RELEASE_DIR=dist/release/stable/1.0.0-1 \
UPDATES_DIR=dist/updates/stable \
HOSTING_DIR=/srv/www/updates/android-dev-agent \
RSYNC_TARGET=deploy@updates.yourcompany.com:/srv/www/updates/android-dev-agent/stable \
CHANNEL=stable \
VERSION=1.0.0 \
BUILD_NUMBER=1 \
bash scripts/promote_release.sh
```

`APPCAST_RSYNC_TARGET` and `RSYNC_TARGET` should point at the final channel directory that serves `appcast.xml`.

Promotion publishes `_rollback/previous` inside the hosted channel so an emergency rollback can run from a fresh CI runner after hydrating the current hosted appcast tree.

## Rollback

Rollback restores the previous published channel snapshot captured during promotion:

```bash
HOSTING_DIR=/srv/www/updates/android-dev-agent \
RSYNC_TARGET=deploy@updates.yourcompany.com:/srv/www/updates/android-dev-agent/stable \
CHANNEL=stable \
bash scripts/rollback_release.sh
```

Use `ROLLBACK_SOURCE=/path/to/snapshot` to restore a specific appcast snapshot instead of the latest previous one.

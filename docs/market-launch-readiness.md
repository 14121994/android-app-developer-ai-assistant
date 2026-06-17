# Market Launch Readiness

This repo now blocks `RELEASE=1` packaging unless the release operator supplies evidence for the external systems that cannot be created by the app bundle itself.

## Release gate

Run the gate directly:

```bash
RELEASE=1 bash scripts/release_readiness_check.sh
```

The packaging script runs the same gate automatically when `RELEASE=1` and `MARKET_READINESS_CHECK` is not disabled.

The end-to-end production runbook is in `docs/release-pipeline.md`.

## Required release configuration

The gate requires these values for a launch candidate:

```text
BUNDLE_ID
SIGNING_IDENTITY
INSTALLER_SIGNING_IDENTITY
NOTARIZE=1
NOTARYTOOL_PROFILE
SPARKLE_PUBLIC_ED_KEY
APPCAST_URL
SPARKLE_ROLLOUT_PLAN_PATH
SPARKLE_ROLLBACK_PLAN_PATH
LICENSE_ACTIVATION_URL
LICENSE_REFRESH_URL
LICENSE_RECOVERY_URL
LICENSE_TRANSFER_URL
LICENSE_POLICY_PATH
PRIVACY_POLICY_URL
DATA_RETENTION_POLICY_PATH
SUPPORT_REDACTION_POLICY_PATH
CRASH_REPORTING_ENDPOINT
SUPPORT_UPLOAD_ENDPOINT
SYMBOL_UPLOAD_ENDPOINT
CRASH_PIPELINE_RUNBOOK_PATH
ANDROID_MATRIX_REPORT_PATH
```

If `NOTARYTOOL_PROFILE` is not used, the gate requires `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`.

When `PROMOTE_RELEASE=1`, the gate also requires an explicit `APPCAST_HOSTING_DIR` or `APPCAST_RSYNC_TARGET` so the release cannot be promoted using the local default hosting folder by accident.

## Evidence expectations

`LICENSE_ACTIVATION_URL`, `LICENSE_REFRESH_URL`, `LICENSE_RECOVERY_URL`, and `LICENSE_TRANSFER_URL` should point to HTTPS backend routes that activate a license key, refresh an entitlement snapshot, send account recovery, and transfer an entitlement away from the current device/account. The app stores only the masked key, account email, device identifier, entitlement id, server-provided trial/subscription dates, and offline grace window.

`LICENSE_POLICY_PATH` should describe activation, entitlement lookup, subscription state, trial length, offline grace, account recovery, license transfer, revocation, and tamper-resistance controls.

`DATA_RETENTION_POLICY_PATH` should define provider payload retention, local logs, telemetry event retention, support-bundle handling, and deletion requests.

`SUPPORT_REDACTION_POLICY_PATH` should list redaction patterns and manual review rules for exported support bundles. The app redacts common key/token/password/signing values before writing support bundles and again before upload, but release support still needs a documented review workflow.

`SUPPORT_UPLOAD_ENDPOINT` should accept consent-gated JSON support bundle uploads with issue IDs, diagnostic version stamps, per-file SHA-256 values, and redacted base64 file payloads.

`SYMBOL_UPLOAD_ENDPOINT` should receive matching dSYM files or symbol metadata for each shipped build so crash reports can be symbolicated by issue ID, bundle ID, version, build, and dSYM UUID.

`CRASH_PIPELINE_RUNBOOK_PATH` should document the symbol upload process, version/build tagging, upload consent, endpoint routing, deduplication, alerting, deletion flow, and how support issue IDs map to crash records.

`SPARKLE_ROLLOUT_PLAN_PATH` and `SPARKLE_ROLLBACK_PLAN_PATH` should name the hosted appcast location, staged rollout percentages, rollback criteria, and verification commands for signed builds.

`ANDROID_MATRIX_REPORT_PATH` should capture the real-world Android integration matrix: Gradle and Android Gradle Plugin versions, Kotlin and Java projects, Compose and XML UI projects, emulators, physical devices, wireless ADB, failing builds, and large repositories.

`APPCAST_HOSTING_DIR` should point at the local mirror of the update channel used by `scripts/promote_release.sh` and `scripts/rollback_release.sh`. `APPCAST_RSYNC_TARGET`, when set, should point at the final hosted channel directory that serves `appcast.xml`.

## Pipeline safeguards

- `scripts/package_macos_app.sh` rebuilds the Sparkle zip after notarization stapling, then generates the appcast from the stapled archive.
- `scripts/verify_release_artifacts.sh` writes `artifact-verification.json` after checking bundle metadata, signatures, notarization staples, package signature, zip contents, and Sparkle appcast signatures.
- `scripts/promote_release.sh` stages appcast hosting files, snapshots the previous channel, promotes the new channel, and writes `promotion-manifest.json`.
- `scripts/rollback_release.sh` restores the previous channel snapshot and writes a rollback manifest.

## Local safeguards already in the app

- Telemetry defaults to Off.
- Diagnostics-only telemetry writes to a writable local log path with a temp fallback.
- Provider sharing is opt-in and audited locally.
- Support bundles redact common secret-shaped values before export and before upload.
- Support bundle upload is disabled until user consent and an HTTPS endpoint are both present.
- Support bundles include issue IDs, diagnostic version stamps, redaction summaries, and crash symbolication manifests.
- Crash capture writes local issue IDs, version/build metadata, dSYM UUID, and a deduplication hint.
- Commercial licensing starts as a bounded local trial, then uses configured activation, entitlement refresh, account recovery, and transfer backend routes. Backend failures on an already verified entitlement enter offline grace only until the stored grace deadline.

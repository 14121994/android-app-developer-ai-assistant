# Android Dev Agent for macOS

Android Dev Agent is now a native macOS workbench for helping developers build and test Android apps. The app runs on macOS, scans a selected Android project folder, creates an execution plan, and can run local Gradle and ADB commands from the desktop.

On launch, the app intentionally starts without a project loaded. Workspace path, file counts, test counts, Gradle status, project files, and Android tool actions appear only after the user chooses or scans a valid Android project directory.

## What It Includes

- Native SwiftUI macOS app
- IDE Companion interface with project tree, prompt composer, patch preview, test console, agent chat, verification panel, and context chips
- Android project scanner for Gradle, Manifest, source, resources, tests, SDK, package, Kotlin, Java, Compose, and XML signals
- Rule-based planning engine with the same MVP coverage from the Android prototype
- Ask the Assistant model orchestration with visible provider-sharing consent, Auto/Fast/Deep/Private routing, TaskDroid Android Planner integration, project file retrieval, OpenAI Responses API fallback, embedding-assisted context ranking, and local fallback when model services are unavailable
- Launch readiness controls for local crash reporting, telemetry opt-in, license activation status, first-run onboarding, support bundle export, and packaged release notes
- Local command runner for `./gradlew testDebugUnitTest`, `./gradlew assembleDebug`, `./gradlew connectedDebugAndroidTest`, `adb devices`, `adb logcat`, targeted app install-and-launch, and log clearing
- Safety gates for workspace boundaries, scoped diffs, undo checkpoints, secret scanning, and confirmation-required device/configuration actions
- Smoke-test suite for planner routing, safety policies, Android workspace scanning, command construction, catalog coverage, and process execution

## macOS Architecture

1. macOS Workbench Interface: SwiftUI prompt, workspace, tool, plan, catalog, and output tabs.
2. Android Workspace Context Engine: scans selected Android project files before planning.
3. Ask Model Orchestration: defaults to a private local route, then routes prompts to TaskDroid `low`/`medium`/`xhigh` planning modes or OpenAI only after provider-sharing consent is enabled.
4. Local Tool Executor: runs Gradle and ADB commands through macOS `Process`.
5. Planning + Verification Loop: converts requests into inspect, patch, build, test, device, and report stages.
6. Safety + Permission Layer: enforces workspace boundaries, diff gates, undo checkpoints, secret redaction, and confirmation rules.

Detailed feature-by-feature architecture designs live in `docs/architecture/README.md`, including dedicated App Store launch-readiness designs for support bundle upload, log redaction, crash symbolication, issue IDs, and diagnostic version stamps.

## Build and Test

```bash
swift test
swift run AndroidDevAgentSmokeTests
swift build -c release
```

The SwiftPM test target runs a build-tool launch gate that covers core planner routing, workspace scanning, command generation, process execution, and model routing configuration even on CLI-only Command Line Tools installs where Apple's XCTest runner is unavailable. The smoke-test executable adds broader app-level coverage for flows that are easier to exercise outside the package test runner.

## Ask Model Setup

Ask the Assistant defaults to Provider Sharing off. In that state, Ask does not send project file excerpts or recent command output to model providers; it answers through the private local route using local project signals. The Ask panel shows the consent switch, the active provider/account status, and whether file excerpts or command output are allowed.

After the user enables Provider Sharing in the Ask panel, Ask can use a configured
TaskDroid Android Planner API or an OpenAI key saved from the in-app Model Setup panel.
TaskDroid is optional and is not assumed to be running on `127.0.0.1`; customer installs
can leave the TaskDroid URL empty and use OpenAI or the private local route instead.

The optional TaskDroid bound model shown in the app is:

```text
taskdroid-android-planner-v1
```

Mode mapping:

- Fast: `intelligence_level=low`
- Auto: `intelligence_level=medium` for simple prompts and `intelligence_level=xhigh` for complex Android implementation/debugging prompts
- Deep: `intelligence_level=xhigh`
- Private: local/private fallback; no provider payload sharing

For internal automation, you can also preconfigure TaskDroid at launch:

```bash
TASKDROID_API_BASE_URL=https://planner.example.com open "dist/Android Dev Agent.app"
```

For the vLLM-backed `taskdroid-android-planner-v1` route, the app waits up to 360 seconds by default before rendering the TaskDroid error. Override that only when needed:

```bash
TASKDROID_API_TIMEOUT_SECONDS=360 TASKDROID_API_BASE_URL=https://planner.example.com open "dist/Android Dev Agent.app"
```

Environment variables remain supported for internal automation, but the market-facing
path is the Ask panel's Model Setup disclosure: save the OpenAI API key to Keychain,
enter a TaskDroid base URL only when the customer has that service, and adjust the
TaskDroid timeout without relaunching from a shell.

When a TaskDroid route is explicitly configured and enabled, Ask the Assistant does not
replace TaskDroid/vLLM failures with OpenAI, local, or deterministic rule output; it
renders the TaskDroid error so model evaluation remains attributable to
`taskdroid-android-planner-v1`. The Ask panel exposes Auto, Fast, Deep, and Private
modes. Private always uses the local/private route and blocks provider payload sharing.

## Package as a macOS App

```bash
bash scripts/package_macos_app.sh
open "dist/Android Dev Agent.app"
```

The package script builds the release binary and creates:

```text
dist/Android Dev Agent.app
```

For market distribution, run the package script in release mode with Developer ID identities,
Sparkle update signing, and notarization credentials:

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
LICENSE_POLICY_PATH=/path/to/license-policy.md \
PRIVACY_POLICY_URL=https://yourcompany.com/privacy/android-dev-agent \
DATA_RETENTION_POLICY_PATH=/path/to/data-retention-policy.md \
SUPPORT_REDACTION_POLICY_PATH=/path/to/support-redaction-policy.md \
CRASH_REPORTING_ENDPOINT=https://crash.yourcompany.com/android-dev-agent \
SUPPORT_UPLOAD_ENDPOINT=https://support.yourcompany.com/android-dev-agent/bundles \
SYMBOL_UPLOAD_ENDPOINT=https://support.yourcompany.com/android-dev-agent/symbols \
CRASH_PIPELINE_RUNBOOK_PATH=/path/to/crash-pipeline-runbook.md \
SPARKLE_ROLLOUT_PLAN_PATH=/path/to/sparkle-rollout-plan.md \
SPARKLE_ROLLBACK_PLAN_PATH=/path/to/sparkle-rollback-plan.md \
ANDROID_MATRIX_REPORT_PATH=/path/to/android-matrix-report.md \
bash scripts/package_macos_app.sh
```

The release script creates a signed `.app`, Sparkle-ready zip archive, installer `.pkg`,
generated app icon, release manifest, artifact verification report, and channel update
directory under `dist/`. If Sparkle's `generate_appcast` tool is available in the
resolved package artifacts, the script also signs and updates the appcast feed for the
configured channel. Generate the Sparkle public key once with Sparkle's `generate_keys`
tool and keep the private key in the release keychain.

When `RELEASE=1`, `scripts/package_macos_app.sh` also runs
`scripts/release_readiness_check.sh`. The gate blocks market packaging until signing,
notarization, hosted Sparkle appcast, license activation/refresh/recovery/transfer
service endpoints, privacy/retention policy, support redaction policy, support upload,
crash pipeline, symbol upload, rollout/rollback plan, and Android integration matrix
evidence are configured. See `docs/market-launch-readiness.md`.

For the full production path, use `docs/release-pipeline.md`. The pipeline includes a
GitHub Actions workflow, Developer ID signing, notarization, artifact verification,
Sparkle appcast signing, appcast hosting promotion, and rollback to the previous hosted
channel snapshot.

Release notes are sourced from `release-notes/$VERSION.md`, generated into the release
directory as `RELEASE_NOTES.md`, embedded into the app bundle resources, and referenced
from `release-manifest.json`. To preview the generated notes without packaging:

```bash
VERSION=1.0.0 BUILD_NUMBER=1 CHANNEL=stable bash scripts/generate_release_notes.sh
```

## Launch Support

The macOS app installs a local crash reporter at launch. Crash reports, launch logs,
privacy audit history, and telemetry event logs stay on the Mac under a writable app
support/log folder with a temporary-directory fallback unless the user explicitly exports
Session > Diagnostics > Launch Readiness > Support Bundle. Support bundles redact common
API keys, bearer tokens, passwords, signing credentials, and secret-shaped values before
export and again before upload. Each bundle includes an issue ID, diagnostic version
stamp, redaction summary, and crash symbolication manifest. Upload remains disabled until
the user enables Support Upload consent and the signed build has `SUPPORT_UPLOAD_ENDPOINT`;
crash upload consent is tracked separately. Telemetry defaults to Off and can be changed
from Settings > Launch. License activation status, entitlement refresh, account recovery,
license transfer, offline grace, and onboarding completion are visible in the same
Settings section and in the Diagnostics launch-readiness card; backend entitlement
operations require the release build to be configured with the license activation,
refresh, recovery, and transfer URLs.

## Android Tooling Requirements

- Android SDK installed on the Mac
- `adb` available through `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `~/Library/Android/sdk/platform-tools/adb`
- Android projects should preferably include a Gradle wrapper (`gradlew`)
- An emulator or physical Android device is needed for ADB/device actions

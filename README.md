# Android Dev Agent for macOS

Android Dev Agent is now a native macOS workbench for helping developers build and test Android apps. The app runs on macOS, scans a selected Android project folder, creates an execution plan, and can run local Gradle and ADB commands from the desktop.

On launch, the app intentionally starts without a project loaded. Workspace path, file counts, test counts, Gradle status, project files, and Android tool actions appear only after the user chooses or scans a valid Android project directory.

## What It Includes

- Native SwiftUI macOS app
- IDE Companion interface with project tree, prompt composer, patch preview, test console, agent chat, verification panel, and context chips
- Android project scanner for Gradle, Manifest, source, resources, tests, SDK, package, Kotlin, Java, Compose, and XML signals
- Rule-based planning engine with the same MVP coverage from the Android prototype
- Ask the Assistant model orchestration with Auto/Fast/Deep/Private routing, TaskDroid Android Planner integration, project file retrieval, OpenAI Responses API fallback, embedding-assisted context ranking, and local fallback when model services are unavailable
- Local command runner for `./gradlew testDebugUnitTest`, `./gradlew assembleDebug`, `./gradlew connectedDebugAndroidTest`, `adb devices`, `adb logcat`, app launch, and log clearing
- Safety gates for workspace boundaries, scoped diffs, undo checkpoints, secret scanning, and confirmation-required device/configuration actions
- Smoke-test suite for planner routing, safety policies, Android workspace scanning, command construction, catalog coverage, and process execution

## macOS Architecture

1. macOS Workbench Interface: SwiftUI prompt, workspace, tool, plan, catalog, and output tabs.
2. Android Workspace Context Engine: scans selected Android project files before planning.
3. Ask Model Orchestration: routes prompts to TaskDroid `low`/`medium`/`high`/`xhigh` planning modes, retrieves relevant files, and can fall back to OpenAI or local responses when configured.
4. Local Tool Executor: runs Gradle and ADB commands through macOS `Process`.
5. Planning + Verification Loop: converts requests into inspect, patch, build, test, device, and report stages.
6. Safety + Permission Layer: enforces workspace boundaries, diff gates, undo checkpoints, secret redaction, and confirmation rules.

## Build and Test

```bash
swift run AndroidDevAgentSmokeTests
swift build -c release
```

The smoke-test executable currently runs 20 cases without relying on XCTest, which keeps verification working on Command Line Tools installs where XCTest is unavailable.

## Ask Model Setup

Ask the Assistant uses the local TaskDroid Android Planner API when it is running. By default, the app calls:

```text
http://127.0.0.1:8000/plan
```

The bound model shown in the app is:

```text
taskdroid-android-planner-v1
```

Mode mapping:

- Fast: `intelligence_level=low`
- Auto: `intelligence_level=medium` for simple prompts and `intelligence_level=xhigh` for complex Android implementation/debugging prompts
- Deep: `intelligence_level=xhigh`
- Private: `intelligence_level=high`

If the TaskDroid API runs on a different address, launch the app with:

```bash
TASKDROID_API_BASE_URL=http://127.0.0.1:8000 open "dist/Android Dev Agent.app"
```

For the local vLLM-backed `taskdroid-android-planner-v1` route, the app waits up to 360 seconds by default before rendering the TaskDroid error. Override that only when needed:

```bash
TASKDROID_API_TIMEOUT_SECONDS=360 TASKDROID_API_BASE_URL=http://127.0.0.1:8000 open "dist/Android Dev Agent.app"
```

When the TaskDroid route is selected, Ask the Assistant does not replace TaskDroid/vLLM failures with OpenAI, local, or deterministic rule output; it renders the TaskDroid error so model evaluation remains attributable to `taskdroid-android-planner-v1`. To enable OpenAI responses for non-TaskDroid fallback paths and embedding-assisted file ranking, launch the app with:

```bash
OPENAI_API_KEY=sk-... open "dist/Android Dev Agent.app"
```

The Ask panel exposes Auto, Fast, Deep, and Private modes. Auto routes simple prompts to the medium TaskDroid route and complex Android development prompts to the xhigh TaskDroid route; Private uses the high TaskDroid route. If TaskDroid/vLLM fails, the app shows the error instead of generating a fallback answer.

## Package as a macOS App

```bash
bash scripts/package_macos_app.sh
open "dist/Android Dev Agent.app"
```

The package script builds the release binary and creates:

```text
dist/Android Dev Agent.app
```

## Android Tooling Requirements

- Android SDK installed on the Mac
- `adb` available through `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `~/Library/Android/sdk/platform-tools/adb`
- Android projects should preferably include a Gradle wrapper (`gradlew`)
- An emulator or physical Android device is needed for ADB/device actions

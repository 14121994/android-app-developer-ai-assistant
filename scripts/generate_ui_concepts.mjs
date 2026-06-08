import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const outDir = path.join(root, "design-concepts");

fs.mkdirSync(outDir, { recursive: true });

const W = 1600;
const H = 1000;

function esc(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function rect(x, y, w, h, fill, stroke = "none", r = 12, opacity = 1) {
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" stroke="${stroke}" opacity="${opacity}"/>`;
}

function line(x1, y1, x2, y2, stroke, width = 1, opacity = 1) {
  return `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${stroke}" stroke-width="${width}" opacity="${opacity}"/>`;
}

function circle(cx, cy, r, fill, stroke = "none", opacity = 1) {
  return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${fill}" stroke="${stroke}" opacity="${opacity}"/>`;
}

function text(value, x, y, size = 24, fill = "#111827", weight = 500, anchor = "start") {
  return `<text x="${x}" y="${y}" fill="${fill}" font-size="${size}" font-weight="${weight}" text-anchor="${anchor}" font-family="-apple-system, BlinkMacSystemFont, 'SF Pro Display', Inter, Arial, sans-serif">${esc(value)}</text>`;
}

function mono(value, x, y, size = 20, fill = "#111827", weight = 500) {
  return `<text x="${x}" y="${y}" fill="${fill}" font-size="${size}" font-weight="${weight}" font-family="'SF Mono', Menlo, Consolas, monospace">${esc(value)}</text>`;
}

function pill(label, x, y, fill, ink, w = undefined) {
  const width = w ?? Math.max(92, label.length * 10 + 34);
  return `${rect(x, y, width, 34, fill, "none", 17)}${text(label, x + 17, y + 23, 15, ink, 700)}`;
}

function navDots(x, y, muted = false) {
  const colors = muted ? ["#6b7280", "#6b7280", "#6b7280"] : ["#ff5f57", "#ffbd2e", "#28c840"];
  return colors.map((c, i) => circle(x + i * 24, y, 8, c)).join("");
}

function sparkline(x, y, color, values, width = 220, height = 70) {
  const step = width / (values.length - 1);
  const max = Math.max(...values);
  const min = Math.min(...values);
  const pts = values.map((v, i) => {
    const px = x + i * step;
    const py = y + height - ((v - min) / Math.max(1, max - min)) * height;
    return `${px.toFixed(1)},${py.toFixed(1)}`;
  }).join(" ");
  return `<polyline points="${pts}" fill="none" stroke="${color}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>`;
}

function progress(x, y, w, pct, color, bg = "#e5e7eb") {
  return `${rect(x, y, w, 10, bg, "none", 5)}${rect(x, y, Math.round(w * pct), 10, color, "none", 5)}`;
}

function sidebar(items, x, y, w, color, activeIndex = 0, dark = false) {
  return items.map((item, i) => {
    const iy = y + i * 56;
    const active = i === activeIndex;
    return [
      active ? rect(x, iy - 26, w, 42, dark ? "#172033" : "#e8f4f2", "none", 8) : "",
      circle(x + 22, iy - 5, 8, active ? color : dark ? "#64748b" : "#94a3b8"),
      text(item, x + 42, iy, 18, active ? color : dark ? "#cbd5e1" : "#475569", active ? 800 : 600)
    ].join("");
  }).join("");
}

function cardTitle(title, subtitle, x, y, ink = "#111827", muted = "#64748b") {
  return `${text(title, x, y, 24, ink, 800)}${subtitle ? text(subtitle, x, y + 32, 15, muted, 600) : ""}`;
}

function terminalLines(lines, x, y, color = "#d1fae5") {
  return lines.map((l, i) => mono(l, x, y + i * 31, 18, i === 0 ? "#7dd3fc" : color, i === 0 ? 800 : 500)).join("");
}

function wrap(svg, bg = "#f6f8fb") {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
  <defs>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">
      <feDropShadow dx="0" dy="18" stdDeviation="24" flood-color="#0f172a" flood-opacity="0.13"/>
    </filter>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="30"/>
    </filter>
    <linearGradient id="tealBlue" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="#0f766e"/>
      <stop offset="1" stop-color="#2563eb"/>
    </linearGradient>
    <linearGradient id="night" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="#07111f"/>
      <stop offset="1" stop-color="#111827"/>
    </linearGradient>
    <linearGradient id="ember" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="#ea580c"/>
      <stop offset="1" stop-color="#be123c"/>
    </linearGradient>
  </defs>
  ${rect(0, 0, W, H, bg, "none", 0)}
  ${svg}
</svg>`;
}

const concepts = [
  {
    slug: "01-command-center",
    name: "Command Center",
    summary: "Dense professional dashboard with project health, plan timeline, tools, and command output.",
    svg: wrap(`
      ${rect(90, 70, 1420, 860, "#ffffff", "#dbe3ea", 22, 1)}
      ${rect(90, 70, 1420, 72, "#f8fafc", "none", 22)}
      ${navDots(130, 106)}
      ${text("Android Dev Agent", 220, 116, 22, "#0f172a", 800)}
      ${pill("Gradle ready", 1250, 88, "#dcfce7", "#15803d", 128)}
      ${pill("89% confidence", 1392, 88, "#dbeafe", "#1d4ed8", 132)}
      ${line(90, 142, 1510, 142, "#e2e8f0")}
      ${rect(90, 142, 270, 788, "#f8fafc", "none", 0)}
      ${sidebar(["Plan", "Workspace", "Android Tools", "Output", "Catalog"], 126, 210, 202, "#0f766e")}
      ${rect(388, 176, 646, 188, "#f9fafb", "#e5e7eb", 16)}
      ${cardTitle("Build login flow", "Create screen, ViewModel validation, tests, emulator check", 420, 222)}
      ${pill("Kotlin", 420, 272, "#ecfeff", "#0e7490", 92)}
      ${pill("Compose-ready", 522, 272, "#eef2ff", "#4338ca", 138)}
      ${pill("Safe patch", 670, 272, "#fef3c7", "#a16207", 116)}
      ${progress(420, 326, 560, .89, "#0f766e")}
      ${rect(1060, 176, 392, 188, "#0f172a", "none", 16)}
      ${terminalLines(["$ ./gradlew testDebugUnitTest", "> 18 tests passed", "> assembleDebug up-to-date", "> emulator screenshot queued"], 1090, 224)}
      ${rect(388, 396, 500, 484, "#ffffff", "#e5e7eb", 16)}
      ${cardTitle("Execution Loop", "Agent stages", 420, 440)}
      ${["Scan workspace", "Design UI state", "Patch files", "Run Gradle", "Inspect device", "Summarize"].map((s, i) => `
        ${circle(438, 505 + i * 55, 13, i < 2 ? "#0f766e" : "#2563eb")}
        ${i < 5 ? line(438, 518 + i * 55, 438, 547 + i * 55, "#cbd5e1", 3) : ""}
        ${text(s, 466, 512 + i * 55, 18, "#1f2937", 750)}
        ${text(i < 2 ? "done" : "queued", 750, 512 + i * 55, 14, i < 2 ? "#0f766e" : "#64748b", 800)}
      `).join("")}
      ${rect(920, 396, 532, 484, "#ffffff", "#e5e7eb", 16)}
      ${cardTitle("Workspace Signals", "Live Android project context", 952, 440)}
      ${["Manifest found", "Gradle wrapper", "Kotlin source", "23 test files", "ADB online", "No secrets detected"].map((s, i) => `
        ${rect(952 + (i % 2) * 230, 488 + Math.floor(i / 2) * 86, 204, 54, i % 3 === 0 ? "#ecfdf5" : i % 3 === 1 ? "#eff6ff" : "#fff7ed", "none", 10)}
        ${text(s, 970 + (i % 2) * 230, 522 + Math.floor(i / 2) * 86, 17, i % 3 === 0 ? "#047857" : i % 3 === 1 ? "#1d4ed8" : "#c2410c", 800)}
      `).join("")}
      ${sparkline(968, 770, "#0f766e", [12, 20, 18, 36, 32, 50, 44, 68])}
      ${text("build stability", 1210, 816, 16, "#64748b", 700)}
    `)
  },
  {
    slug: "02-midnight-terminal",
    name: "Midnight Terminal",
    summary: "Dark command-first interface with chat, terminal telemetry, and Android tool launchers.",
    svg: wrap(`
      ${rect(0, 0, W, H, "url(#night)", "none", 0)}
      ${circle(1300, 160, 220, "#0f766e", "none", .22)}
      ${circle(260, 840, 210, "#2563eb", "none", .18)}
      ${rect(86, 68, 1428, 864, "#0b1220", "#1e293b", 24, .94)}
      ${navDots(130, 105, true)}
      ${text("Midnight Agent Console", 220, 114, 24, "#f8fafc", 800)}
      ${pill("device: Pixel 8", 1170, 88, "#0f2f2d", "#5eead4", 144)}
      ${pill("logs armed", 1328, 88, "#2a1621", "#fb7185", 114)}
      ${rect(120, 160, 360, 724, "#101827", "#263244", 18)}
      ${text("Prompt", 150, 208, 21, "#e5e7eb", 800)}
      ${rect(150, 235, 300, 176, "#0f172a", "#334155", 14)}
      ${text("Fix a crash after", 174, 278, 22, "#f8fafc", 750)}
      ${text("sign-in rotation", 174, 311, 22, "#f8fafc", 750)}
      ${text("and verify on", 174, 344, 22, "#94a3b8", 650)}
      ${text("the emulator.", 174, 377, 22, "#94a3b8", 650)}
      ${sidebar(["Crash triage", "Safe patch", "Unit tests", "ADB replay", "Summary"], 150, 486, 280, "#5eead4", 0, true)}
      ${rect(520, 160, 574, 724, "#020617", "#1e293b", 18)}
      ${text("Live Execution", 552, 210, 24, "#f8fafc", 850)}
      ${terminalLines([
        "$ adb logcat -d -t 250",
        "E AndroidRuntime: FATAL EXCEPTION main",
        "Caused by: NullPointerException",
        "at LoginViewModel.restoreSession",
        "",
        "$ ./gradlew testDebugUnitTest",
        "> LoginViewModelTest passed",
        "> SessionRepositoryTest passed",
        "",
        "$ adb shell input tap 842 712",
        "> screenshot captured",
        "> contrast checks queued"
      ], 552, 260, "#cbd5e1")}
      ${rect(1134, 160, 338, 724, "#111827", "#263244", 18)}
      ${text("Tool Dock", 1166, 210, 24, "#f8fafc", 850)}
      ${["Build", "Test", "Logcat", "Install", "Launch", "Screenshot"].map((s, i) => `
        ${rect(1166, 246 + i * 78, 274, 54, i % 2 ? "#172033" : "#0f172a", "#334155", 10)}
        ${circle(1192, 273 + i * 78, 10, i < 3 ? "#5eead4" : "#93c5fd")}
        ${text(s, 1216, 281 + i * 78, 18, "#f8fafc", 800)}
      `).join("")}
      ${rect(1166, 770, 274, 72, "#0f2f2d", "#134e4a", 12)}
      ${text("Safety gates active", 1190, 814, 18, "#5eead4", 800)}
    `, "#07111f")
  },
  {
    slug: "03-glass-lab",
    name: "Glass Lab",
    summary: "macOS-style translucent panels with airy planning, device preview, and soft status surfaces.",
    svg: wrap(`
      ${rect(0, 0, W, H, "#eef7f6", "none", 0)}
      ${circle(250, 170, 190, "#5eead4", "none", .32)}
      ${circle(1260, 840, 240, "#93c5fd", "none", .34)}
      ${circle(1000, 160, 160, "#fda4af", "none", .22)}
      ${rect(92, 74, 1416, 852, "#ffffff", "#ffffff", 24, .62)}
      ${rect(124, 112, 1352, 72, "#ffffff", "#dbeafe", 18, .72)}
      ${navDots(162, 148)}
      ${text("Glass Lab Workbench", 250, 158, 24, "#0f172a", 850)}
      ${pill("Compose detected", 1160, 130, "#ffffff", "#0f766e", 158)}
      ${pill("ADB online", 1330, 130, "#ffffff", "#2563eb", 120)}
      ${rect(124, 218, 372, 660, "#ffffff", "#d7e4ed", 22, .76)}
      ${text("Request", 158, 268, 24, "#0f172a", 850)}
      ${rect(158, 298, 304, 154, "#f8fafc", "#dbe3ea", 16, .88)}
      ${text("Create onboarding", 184, 342, 23, "#0f172a", 800)}
      ${text("flow with tests", 184, 376, 23, "#0f172a", 800)}
      ${text("and screenshots.", 184, 410, 23, "#64748b", 700)}
      ${["Index", "Patch", "Build", "Verify"].map((s, i) => `
        ${rect(158, 500 + i * 74, 304, 52, "#ffffff", "#dbe3ea", 14, .9)}
        ${text(s, 190, 533 + i * 74, 19, "#0f172a", 800)}
        ${text(i < 1 ? "done" : "next", 382, 533 + i * 74, 15, i < 1 ? "#0f766e" : "#2563eb", 800)}
      `).join("")}
      ${rect(532, 218, 520, 660, "#ffffff", "#d7e4ed", 22, .76)}
      ${text("Plan Canvas", 568, 268, 26, "#0f172a", 850)}
      ${["Workspace scan", "UI state model", "Safe diff preview", "Gradle verification", "Device inspection"].map((s, i) => `
        ${circle(594, 330 + i * 82, 16, i === 0 ? "#0f766e" : "#2563eb")}
        ${line(594, 346 + i * 82, 594, 390 + i * 82, "#cbd5e1", 4, i < 4 ? 1 : 0)}
        ${text(s, 630, 338 + i * 82, 20, "#172033", 800)}
        ${text("Tool routing and safety notes", 630, 365 + i * 82, 15, "#64748b", 600)}
      `).join("")}
      ${rect(1088, 218, 388, 660, "#ffffff", "#d7e4ed", 22, .76)}
      ${text("Device Preview", 1124, 268, 26, "#0f172a", 850)}
      ${rect(1170, 308, 222, 440, "#111827", "#334155", 32)}
      ${rect(1194, 342, 174, 32, "#0f766e", "none", 10)}
      ${rect(1194, 402, 174, 96, "#f8fafc", "none", 14)}
      ${rect(1214, 524, 134, 16, "#dbeafe", "none", 8)}
      ${rect(1214, 556, 134, 16, "#dbeafe", "none", 8)}
      ${rect(1230, 646, 102, 42, "#2563eb", "none", 18)}
      ${text("screenshot ok", 1176, 804, 18, "#0f766e", 800)}
    `)
  },
  {
    slug: "04-kanban-agent",
    name: "Kanban Agent",
    summary: "Workflow-board UI where the agent moves Android work through inspect, edit, test, and ship columns.",
    svg: wrap(`
      ${rect(70, 58, 1460, 884, "#fbfbfc", "#d7dde5", 24)}
      ${text("Kanban Agent", 116, 126, 34, "#111827", 900)}
      ${text("Android tasks move from request to verified result", 116, 158, 17, "#64748b", 600)}
      ${pill("Workspace scanned", 1140, 106, "#dcfce7", "#15803d", 160)}
      ${pill("5 stages", 1316, 106, "#eef2ff", "#4338ca", 104)}
      ${["Request", "Inspect", "Patch", "Verify", "Report"].map((col, i) => {
        const x = 116 + i * 290;
        return `
          ${rect(x, 204, 250, 650, "#f1f5f9", "#dbe3ea", 18)}
          ${text(col, x + 20, 248, 22, "#111827", 850)}
          ${[0, 1, 2].map((_, j) => {
            const labels = [
              ["Login flow", "Auth screen + validation", "MVP"],
              ["Gradle files", "Dependencies + Manifest", "Safe"],
              ["ViewModel", "State + test surface", "Code"],
              ["Diff preview", "Scoped changes", "Gate"],
              ["Unit tests", "Local JVM suite", "Test"],
              ["ADB replay", "Launch + screenshot", "Device"],
              ["Build health", "assembleDebug", "Build"],
              ["Logcat", "Crash-free pass", "Logs"],
              ["Screenshots", "Layout review", "UI"],
              ["Summary", "Files + results", "Done"],
              ["Next action", "Open PR notes", "Ship"],
              ["Memory", "Persist prefs", "Core"],
              ["Coverage", "Risks listed", "QA"],
              ["Release", "Ready check", "Later"],
              ["Archive", "Undo point kept", "Safe"]
            ];
            const item = labels[i * 3 + j];
            return `
              ${rect(x + 18, 286 + j * 158, 214, 118, "#ffffff", "#dbe3ea", 14)}
              ${text(item[0], x + 38, 326 + j * 158, 20, "#111827", 850)}
              ${text(item[1], x + 38, 354 + j * 158, 15, "#64748b", 600)}
              ${pill(item[2], x + 38, 374 + j * 158, i < 2 ? "#ecfdf5" : i < 4 ? "#eff6ff" : "#fef3c7", i < 2 ? "#047857" : i < 4 ? "#1d4ed8" : "#a16207", 84)}
            `;
          }).join("")}
        `;
      }).join("")}
    `)
  },
  {
    slug: "05-ide-companion",
    name: "IDE Companion",
    summary: "Android Studio-inspired layout with file context, AI chat, diff preview, and test console.",
    svg: wrap(`
      ${rect(72, 58, 1456, 884, "#ffffff", "#d1d5db", 18)}
      ${rect(72, 58, 1456, 58, "#eef2f7", "none", 18)}
      ${navDots(108, 88)}
      ${text("IDE Companion", 204, 96, 22, "#111827", 850)}
      ${rect(72, 116, 294, 826, "#f8fafc", "none", 0)}
      ${text("Project", 104, 166, 22, "#111827", 850)}
      ${[
        ["app", 0], ["src/main", 1], ["LoginScreen.kt", 2], ["LoginViewModel.kt", 2],
        ["AndroidManifest.xml", 1], ["build.gradle", 1], ["src/test", 1], ["LoginViewModelTest.kt", 2]
      ].map(([s, indent], i) => `
        ${rect(104 + indent * 18, 204 + i * 42, 220 - indent * 18, 30, i === 2 ? "#e0f2fe" : "transparent", "none", 6)}
        ${text(s, 116 + indent * 18, 226 + i * 42, 16, i === 2 ? "#0369a1" : "#475569", i === 2 ? 850 : 650)}
      `).join("")}
      ${rect(390, 146, 610, 470, "#0b1220", "#1f2937", 14)}
      ${text("Diff Preview", 424, 194, 22, "#f8fafc", 850)}
      ${mono("@Composable", 424, 246, 18, "#93c5fd", 700)}
      ${mono("+ fun LoginScreen(state: LoginState)", 424, 282, 18, "#86efac", 700)}
      ${mono("+ TextField(value = state.email)", 424, 318, 18, "#86efac", 700)}
      ${mono("+ Button(enabled = state.isValid)", 424, 354, 18, "#86efac", 700)}
      ${mono("- TODO placeholder UI", 424, 390, 18, "#fca5a5", 700)}
      ${mono("+ Semantics { contentDescription = ... }", 424, 426, 18, "#86efac", 700)}
      ${rect(390, 642, 610, 250, "#111827", "#1f2937", 14)}
      ${terminalLines(["$ ./gradlew testDebugUnitTest", "> LoginViewModelTest PASSED", "> assembleDebug PASSED", "> no lint baseline changes"], 424, 696, "#d1fae5")}
      ${rect(1030, 146, 454, 746, "#ffffff", "#dbe3ea", 14)}
      ${text("Agent Chat", 1064, 194, 22, "#111827", 850)}
      ${[
        ["User", "Create a login screen with validation."],
        ["Agent", "I found Compose, MVVM, and 18 tests."],
        ["Agent", "Patch touches 3 files and adds 2 tests."],
        ["Agent", "Ready to run emulator verification."]
      ].map(([who, msg], i) => `
        ${rect(1064, 232 + i * 108, 386, 76, who === "User" ? "#eff6ff" : "#ecfdf5", "none", 14)}
        ${text(who, 1088, 262 + i * 108, 15, who === "User" ? "#1d4ed8" : "#047857", 850)}
        ${text(msg, 1088, 288 + i * 108, 17, "#1f2937", 650)}
      `).join("")}
      ${rect(1064, 806, 386, 46, "#0f766e", "none", 10)}
      ${text("Apply Safe Patch", 1257, 836, 17, "#ffffff", 850, "middle")}
    `)
  },
  {
    slug: "06-device-farm",
    name: "Device Farm",
    summary: "Visual device-first UI for emulator testing, screenshot review, Logcat, and interaction replay.",
    svg: wrap(`
      ${rect(78, 62, 1444, 876, "#ffffff", "#dbe3ea", 24)}
      ${text("Device Farm", 126, 130, 34, "#111827", 900)}
      ${text("Run, inspect, and compare Android behavior from macOS", 126, 162, 17, "#64748b", 600)}
      ${rect(126, 210, 420, 666, "#f8fafc", "#e5e7eb", 18)}
      ${text("ADB Actions", 160, 260, 24, "#111827", 850)}
      ${["List devices", "Install debug", "Launch app", "Tap replay", "Screenshot", "Logcat triage"].map((s, i) => `
        ${rect(160, 296 + i * 76, 352, 52, i === 3 ? "#0f766e" : "#ffffff", "#dbe3ea", 12)}
        ${text(s, 188, 330 + i * 76, 19, i === 3 ? "#ffffff" : "#111827", 800)}
      `).join("")}
      ${rect(590, 210, 520, 666, "#111827", "#1f2937", 18)}
      ${text("Pixel 8 Preview", 626, 260, 24, "#f8fafc", 850)}
      ${rect(736, 296, 230, 454, "#020617", "#334155", 34)}
      ${rect(758, 336, 186, 38, "#0f766e", "none", 12)}
      ${rect(758, 400, 186, 110, "#f8fafc", "none", 16)}
      ${rect(780, 532, 142, 18, "#dbeafe", "none", 9)}
      ${rect(780, 568, 142, 18, "#dbeafe", "none", 9)}
      ${rect(802, 656, 98, 44, "#2563eb", "none", 20)}
      ${text("frame 14 / 18", 790, 804, 18, "#93c5fd", 800)}
      ${rect(1154, 210, 320, 666, "#f8fafc", "#e5e7eb", 18)}
      ${text("Inspection", 1188, 260, 24, "#111827", 850)}
      ${["No clipping", "Contrast 4.8", "Tap target 48dp", "Crash-free", "Logcat clean"].map((s, i) => `
        ${circle(1202, 320 + i * 72, 11, i < 4 ? "#0f766e" : "#f59e0b")}
        ${text(s, 1228, 327 + i * 72, 19, "#111827", 780)}
      `).join("")}
      ${sparkline(1194, 734, "#2563eb", [30, 44, 35, 60, 58, 73, 68, 90], 220, 80)}
      ${text("stability", 1230, 846, 17, "#64748b", 800)}
    `)
  },
  {
    slug: "07-build-radar",
    name: "Build Radar",
    summary: "Observability-heavy dashboard for builds, tests, crashes, dependencies, and confidence signals.",
    svg: wrap(`
      ${rect(64, 54, 1472, 892, "#0f172a", "#1e293b", 24)}
      ${text("Build Radar", 112, 124, 34, "#f8fafc", 900)}
      ${text("Android project telemetry with agent recommendations", 112, 156, 17, "#94a3b8", 600)}
      ${["Compile", "Tests", "Logcat", "Deps"].map((s, i) => `
        ${rect(112 + i * 356, 206, 316, 178, "#111827", "#334155", 16)}
        ${text(s, 142 + i * 356, 252, 20, "#f8fafc", 850)}
        ${text(["98%", "87%", "clean", "3 alerts"][i], 142 + i * 356, 318, 44, i === 2 ? "#5eead4" : i === 3 ? "#fbbf24" : "#93c5fd", 900)}
        ${progress(142 + i * 356, 344, 240, [0.98, .87, .74, .48][i], i === 3 ? "#f59e0b" : "#0f766e", "#1e293b")}
      `).join("")}
      ${rect(112, 424, 676, 420, "#111827", "#334155", 18)}
      ${text("Risk Map", 150, 478, 24, "#f8fafc", 850)}
      ${[0, 1, 2, 3, 4].map((r) => [0, 1, 2, 3, 4, 5, 6].map((c) => {
        const colors = ["#0f766e", "#2563eb", "#f59e0b", "#be123c"];
        return rect(150 + c * 82, 520 + r * 52, 58, 32, colors[(r + c) % 4], "none", 8, .78);
      }).join("")).join("")}
      ${text("Manifest", 150, 812, 17, "#94a3b8", 700)}
      ${text("Gradle", 290, 812, 17, "#94a3b8", 700)}
      ${text("Runtime", 430, 812, 17, "#94a3b8", 700)}
      ${rect(828, 424, 596, 420, "#111827", "#334155", 18)}
      ${text("Agent Recommendation", 866, 478, 24, "#f8fafc", 850)}
      ${["Pin Room version to catalog", "Add missing ViewModel test", "Run connectedDebugAndroidTest", "Capture screenshot after patch"].map((s, i) => `
        ${rect(866, 526 + i * 72, 508, 48, "#0f172a", "#334155", 10)}
        ${circle(890, 550 + i * 72, 9, i < 2 ? "#f59e0b" : "#2563eb")}
        ${text(s, 914, 557 + i * 72, 18, "#e5e7eb", 750)}
      `).join("")}
      ${sparkline(900, 770, "#5eead4", [10, 20, 25, 22, 40, 48, 62, 58, 79], 410, 60)}
    `, "#0f172a")
  },
  {
    slug: "08-split-brain-chat",
    name: "Split Brain Chat",
    summary: "Conversational left side, code/diff middle, verification right side for natural agent flow.",
    svg: wrap(`
      ${rect(78, 58, 1444, 884, "#ffffff", "#dbe3ea", 24)}
      ${text("Split Brain Chat", 124, 128, 34, "#111827", 900)}
      ${pill("conversation", 1080, 106, "#eef2ff", "#4338ca", 144)}
      ${pill("verified edits", 1240, 106, "#dcfce7", "#15803d", 142)}
      ${rect(124, 190, 402, 694, "#f8fafc", "#e5e7eb", 18)}
      ${text("Chat", 158, 240, 24, "#111827", 850)}
      ${[
        ["You", "Add offline cache for feed."],
        ["Agent", "I found Retrofit, Room, and Flow."],
        ["You", "Keep the repository API stable."],
        ["Agent", "Patch plan is scoped to 4 files."]
      ].map(([who, msg], i) => `
        ${rect(158, 278 + i * 116, 334, 80, who === "You" ? "#eff6ff" : "#ecfdf5", "none", 16)}
        ${text(who, 184, 310 + i * 116, 15, who === "You" ? "#1d4ed8" : "#047857", 850)}
        ${text(msg, 184, 338 + i * 116, 18, "#111827", 650)}
      `).join("")}
      ${rect(558, 190, 512, 694, "#0b1220", "#1e293b", 18)}
      ${text("Patch Preview", 594, 240, 24, "#f8fafc", 850)}
      ${mono("+ @Entity(tableName = \"feed_cache\")", 594, 300, 18, "#86efac", 700)}
      ${mono("+ data class CachedFeedItem(...)", 594, 338, 18, "#86efac", 700)}
      ${mono("+ interface FeedDao", 594, 376, 18, "#86efac", 700)}
      ${mono("+ fun observeFeed(): Flow<List<Item>>", 594, 414, 18, "#86efac", 700)}
      ${mono("~ FeedRepository keeps public API", 594, 452, 18, "#fde68a", 700)}
      ${rect(594, 694, 420, 74, "#11201e", "#134e4a", 12)}
      ${text("Undo checkpoint will be created before apply", 620, 738, 18, "#5eead4", 800)}
      ${rect(1102, 190, 374, 694, "#f8fafc", "#e5e7eb", 18)}
      ${text("Verification", 1136, 240, 24, "#111827", 850)}
      ${["testDebugUnitTest", "assembleDebug", "connectedDebugAndroidTest", "adb logcat"].map((s, i) => `
        ${rect(1136, 286 + i * 94, 306, 62, "#ffffff", "#dbe3ea", 12)}
        ${circle(1162, 317 + i * 94, 10, i < 2 ? "#0f766e" : "#2563eb")}
        ${text(s, 1188, 324 + i * 94, 17, "#111827", 780)}
      `).join("")}
      ${rect(1136, 738, 306, 82, "#0f766e", "none", 14)}
      ${text("Ready for review", 1289, 789, 22, "#ffffff", 850, "middle")}
    `)
  },
  {
    slug: "09-release-cockpit",
    name: "Release Cockpit",
    summary: "Ship-focused interface for final verification, signing risks, store readiness, and release notes.",
    svg: wrap(`
      ${rect(70, 58, 1460, 884, "#fffdf8", "#eadfcd", 24)}
      ${text("Release Cockpit", 116, 128, 34, "#1c1917", 900)}
      ${text("From feature branch to confident Android release", 116, 160, 17, "#78716c", 600)}
      ${rect(116, 210, 418, 666, "#ffffff", "#eadfcd", 18)}
      ${text("Readiness", 150, 260, 24, "#1c1917", 850)}
      ${circle(325, 440, 136, "#fef3c7", "#f59e0b")}
      ${text("84%", 325, 456, 54, "#92400e", 900, "middle")}
      ${text("release confidence", 325, 492, 17, "#78716c", 800, "middle")}
      ${["Tests passed", "Manifest checked", "Signing pending", "R8 rules reviewed"].map((s, i) => `
        ${circle(168, 630 + i * 56, 10, i < 2 ? "#0f766e" : i === 2 ? "#f59e0b" : "#2563eb")}
        ${text(s, 194, 637 + i * 56, 18, "#1c1917", 760)}
      `).join("")}
      ${rect(574, 210, 434, 666, "#ffffff", "#eadfcd", 18)}
      ${text("Checklist", 608, 260, 24, "#1c1917", 850)}
      ${["assembleRelease", "lintVitalRelease", "dependency review", "privacy labels", "release notes", "rollback plan"].map((s, i) => `
        ${rect(608, 304 + i * 78, 366, 50, i < 2 ? "#ecfdf5" : i === 3 ? "#fff7ed" : "#f8fafc", "#e7dcc8", 12)}
        ${text(s, 636, 337 + i * 78, 18, "#1c1917", 780)}
      `).join("")}
      ${rect(1048, 210, 390, 666, "#1c1917", "#292524", 18)}
      ${text("Release Notes", 1084, 260, 24, "#fff7ed", 850)}
      ${terminalLines([
        "v1.4.0",
        "- New login recovery flow",
        "- Offline cache stability",
        "- Crash fix on rotation",
        "- Updated dependency catalog",
        "",
        "Risk: signing key not loaded",
        "Next: run release checklist"
      ], 1084, 314, "#fed7aa")}
      ${rect(1084, 790, 318, 52, "#ea580c", "none", 12)}
      ${text("Run Final Checks", 1243, 824, 18, "#ffffff", 850, "middle")}
    `, "#fffdf8")
  },
  {
    slug: "10-minimal-zen",
    name: "Minimal Zen",
    summary: "Calm focused UI with fewer panels, bigger typography, and one clear next action.",
    svg: wrap(`
      ${rect(0, 0, W, H, "#f7f8fa", "none", 0)}
      ${rect(138, 86, 1324, 828, "#ffffff", "#e5e7eb", 28)}
      ${text("Android Dev Agent", 196, 172, 42, "#111827", 900)}
      ${text("Tell the agent what to build, then review the plan before it touches files.", 198, 218, 19, "#64748b", 600)}
      ${rect(196, 276, 820, 156, "#f8fafc", "#e5e7eb", 18)}
      ${text("Create a settings screen, add validation tests, and verify on emulator.", 232, 346, 26, "#111827", 760)}
      ${rect(1048, 276, 216, 156, "#0f766e", "none", 18)}
      ${text("Generate", 1156, 356, 24, "#ffffff", 850, "middle")}
      ${rect(1284, 276, 122, 156, "#eff6ff", "#dbeafe", 18)}
      ${text("91%", 1345, 350, 36, "#1d4ed8", 900, "middle")}
      ${text("ready", 1345, 382, 15, "#1d4ed8", 800, "middle")}
      ${rect(196, 486, 372, 300, "#ffffff", "#e5e7eb", 18)}
      ${text("Plan", 230, 536, 24, "#111827", 850)}
      ${["Scan", "Patch", "Test", "Inspect"].map((s, i) => `
        ${circle(244, 590 + i * 52, 10, i === 0 ? "#0f766e" : "#2563eb")}
        ${text(s, 270, 597 + i * 52, 20, "#111827", 760)}
      `).join("")}
      ${rect(614, 486, 372, 300, "#ffffff", "#e5e7eb", 18)}
      ${text("Tools", 648, 536, 24, "#111827", 850)}
      ${["Gradle", "ADB", "Logcat", "Diffs"].map((s, i) => pill(s, 648 + (i % 2) * 140, 582 + Math.floor(i / 2) * 76, i < 2 ? "#ecfdf5" : "#eff6ff", i < 2 ? "#047857" : "#1d4ed8", 110)).join("")}
      ${rect(1032, 486, 374, 300, "#ffffff", "#e5e7eb", 18)}
      ${text("Safety", 1066, 536, 24, "#111827", 850)}
      ${["Scoped diff", "Undo point", "Secret scan", "Confirm risky actions"].map((s, i) => `
        ${text("✓", 1068, 590 + i * 48, 20, "#0f766e", 900)}
        ${text(s, 1100, 590 + i * 48, 19, "#111827", 700)}
      `).join("")}
      ${text("One calm surface for focused Android development.", 800, 860, 18, "#64748b", 700, "middle")}
    `)
  }
];

for (const concept of concepts) {
  const file = path.join(outDir, `${concept.slug}.svg`);
  fs.writeFileSync(file, concept.svg, "utf8");
}

const gallery = `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Android Dev Agent UI Concepts</title>
  <style>
    body { margin: 0; padding: 32px; font: 15px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; background: #f6f8fb; color: #111827; }
    h1 { margin: 0 0 8px; font-size: 30px; }
    p { color: #64748b; margin: 0 0 28px; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(460px, 1fr)); gap: 22px; }
    .card { background: white; border: 1px solid #e5e7eb; border-radius: 14px; overflow: hidden; box-shadow: 0 16px 36px rgba(15,23,42,.08); }
    img { display: block; width: 100%; height: auto; }
    .meta { padding: 14px 16px 18px; }
    .meta h2 { font-size: 18px; margin: 0 0 6px; }
    .meta p { margin: 0; }
  </style>
</head>
<body>
  <h1>Android Dev Agent UI Concepts</h1>
  <p>Pick one concept number and I will implement that design direction in the macOS SwiftUI app.</p>
  <div class="grid">
    ${concepts.map((c, i) => `
    <section class="card">
      <img src="${c.slug}.svg" alt="${i + 1}. ${esc(c.name)}" />
      <div class="meta">
        <h2>${i + 1}. ${esc(c.name)}</h2>
        <p>${esc(c.summary)}</p>
      </div>
    </section>`).join("")}
  </div>
</body>
</html>`;

fs.writeFileSync(path.join(outDir, "index.html"), gallery, "utf8");

console.log(`Generated ${concepts.length} UI concepts in ${outDir}`);

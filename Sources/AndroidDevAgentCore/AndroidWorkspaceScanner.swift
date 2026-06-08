import Foundation

public final class AndroidWorkspaceScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(rootPath: String) -> WorkspaceSnapshot {
        let root = URL(fileURLWithPath: rootPath)
        let gradlew = root.appendingPathComponent("gradlew").path
        let settingsGradle = root.appendingPathComponent("settings.gradle").path
        let settingsGradleKts = root.appendingPathComponent("settings.gradle.kts").path
        let appGradle = root.appendingPathComponent("app/build.gradle").path
        let appGradleKts = root.appendingPathComponent("app/build.gradle.kts").path

        var fileCount = 0
        var testFileCount = 0
        var hasManifest = false
        var usesCompose = false
        var usesKotlin = false
        var usesJava = false
        var usesXMLLayouts = false
        var manifestText = ""

        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let path = fileURL.path
                if shouldSkip(path: path) {
                    continue
                }

                guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    continue
                }

                fileCount += 1
                let lowerPath = path.lowercased()
                if lowerPath.contains("/test/") || lowerPath.contains("/androidtest/") {
                    testFileCount += 1
                }
                if lowerPath.hasSuffix(".kt") {
                    usesKotlin = true
                }
                if lowerPath.hasSuffix(".java") {
                    usesJava = true
                }
                if lowerPath.contains("/res/layout/") && lowerPath.hasSuffix(".xml") {
                    usesXMLLayouts = true
                }
                if lowerPath.hasSuffix("androidmanifest.xml") {
                    hasManifest = true
                    manifestText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? manifestText
                }
                if lowerPath.hasSuffix(".kt"),
                   let text = try? String(contentsOf: fileURL, encoding: .utf8),
                   text.contains("@Composable") {
                    usesCompose = true
                }
            }
        }

        let gradleText = [
            read(appGradle),
            read(appGradleKts),
            read(settingsGradle),
            read(settingsGradleKts)
        ].joined(separator: "\n")

        if gradleText.localizedCaseInsensitiveContains("compose") {
            usesCompose = true
        }

        let packageName = firstMatch(
            in: gradleText + "\n" + manifestText,
            patterns: [
                #"applicationId\s+["']([^"']+)["']"#,
                #"applicationId\s*=\s*["']([^"']+)["']"#,
                #"namespace\s+["']([^"']+)["']"#,
                #"namespace\s*=\s*["']([^"']+)["']"#,
                #"package\s*=\s*["']([^"']+)["']"#
            ]
        )

        let minSDK = firstInt(
            in: gradleText,
            patterns: [
                #"minSdk\s+(\d+)"#,
                #"minSdk\s*=\s*(\d+)"#,
                #"minSdkVersion\s+(\d+)"#
            ]
        )

        let targetSDK = firstInt(
            in: gradleText,
            patterns: [
                #"targetSdk\s+(\d+)"#,
                #"targetSdk\s*=\s*(\d+)"#,
                #"targetSdkVersion\s+(\d+)"#
            ]
        )

        return WorkspaceSnapshot(
            rootPath: rootPath,
            fileCount: fileCount,
            testFileCount: testFileCount,
            hasGradleWrapper: fileManager.fileExists(atPath: gradlew),
            hasSettingsGradle: fileManager.fileExists(atPath: settingsGradle) || fileManager.fileExists(atPath: settingsGradleKts),
            hasAndroidManifest: hasManifest,
            usesCompose: usesCompose,
            usesKotlin: usesKotlin,
            usesJava: usesJava,
            usesXMLLayouts: usesXMLLayouts,
            packageName: packageName,
            minSDK: minSDK,
            targetSDK: targetSDK
        )
    }

    private func shouldSkip(path: String) -> Bool {
        let blocked = ["/.gradle/", "/.idea/", "/build/", "/.build/", "/DerivedData/", "/dist/"]
        return blocked.contains { path.contains($0) }
    }

    private func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func firstMatch(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[range])
        }
        return nil
    }

    private func firstInt(in text: String, patterns: [String]) -> Int? {
        guard let value = firstMatch(in: text, patterns: patterns) else {
            return nil
        }
        return Int(value)
    }
}

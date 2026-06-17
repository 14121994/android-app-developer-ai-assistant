import AndroidDevAgentCore
import Foundation

@MainActor
extension AgentViewModel {
    func makeProjectFiles(rootPath: String, snapshot: WorkspaceSnapshot) -> [ProjectFileItem] {
        let rootURL = URL(fileURLWithPath: rootPath)
        var relativeFilePaths: [String] = []
        var seenPaths = Set<String>()

        func appendFile(relativePath: String) {
            guard seenPaths.insert(relativePath).inserted else { return }
            relativeFilePaths.append(relativePath)
        }

        let importantPaths = [
            "settings.gradle",
            "settings.gradle.kts",
            "build.gradle",
            "build.gradle.kts",
            "gradle/libs.versions.toml",
            "app/build.gradle",
            "app/build.gradle.kts",
            "app/src/main/AndroidManifest.xml"
        ]

        for relativePath in importantPaths {
            let absolute = rootURL.appendingPathComponent(relativePath).path
            if FileManager.default.fileExists(atPath: absolute) {
                appendFile(relativePath: relativePath)
            }
        }

        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                let path = url.path
                guard relativeFilePaths.count < 1_000 else { break }
                if shouldSkipProjectTreePath(path) {
                    enumerator.skipDescendants()
                    continue
                }
                guard shouldShowSourcePath(path), let relative = relativePath(for: path, rootPath: rootPath) else {
                    continue
                }
                appendFile(relativePath: relative)
            }
        }

        return makeProjectFileTree(from: relativeFilePaths)
    }

    func makeProjectFileTree(from relativeFilePaths: [String]) -> [ProjectFileItem] {
        var directoryPaths = Set<String>()
        let filePaths = Set(relativeFilePaths)

        for relativePath in relativeFilePaths {
            directoryPaths.formUnion(ancestorFolderPaths(for: relativePath))
        }

        let allPaths = Array(directoryPaths.union(filePaths)).sorted {
            projectTreeSort($0, before: $1, directoryPaths: directoryPaths)
        }

        return allPaths.map { relativePath in
            fileItem(
                relativePath: relativePath,
                selected: !directoryPaths.contains(relativePath) && isKeyProjectFile(relativePath),
                isDirectory: directoryPaths.contains(relativePath)
            )
        }
    }

    func isVisibleInCollapsedFileTree(_ item: ProjectFileItem) -> Bool {
        guard item.depth > 0 else { return true }
        return ancestorFolderPaths(for: item.path).allSatisfy { expandedProjectFolderPaths.contains($0) }
    }

    func ancestorFolderPaths(for relativePath: String) -> [String] {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).map { count in
            parts.prefix(count).joined(separator: "/")
        }
    }

    func isDescendant(_ path: String, of folderPath: String) -> Bool {
        path.hasPrefix(folderPath + "/")
    }

    func projectTreeSort(_ lhs: String, before rhs: String, directoryPaths: Set<String>) -> Bool {
        let leftParts = lhs.split(separator: "/").map(String.init)
        let rightParts = rhs.split(separator: "/").map(String.init)
        let sharedCount = min(leftParts.count, rightParts.count)

        for index in 0..<sharedCount where leftParts[index] != rightParts[index] {
            let leftPath = leftParts.prefix(index + 1).joined(separator: "/")
            let rightPath = rightParts.prefix(index + 1).joined(separator: "/")
            let leftIsDirectory = directoryPaths.contains(leftPath)
            let rightIsDirectory = directoryPaths.contains(rightPath)
            if leftIsDirectory != rightIsDirectory {
                return leftIsDirectory
            }
            return leftParts[index].localizedStandardCompare(rightParts[index]) == .orderedAscending
        }

        return leftParts.count < rightParts.count
    }

    func shouldShowSourcePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard lower.hasSuffix(".kt") || lower.hasSuffix(".java") || lower.hasSuffix(".xml") else {
            return false
        }
        return !lower.contains("/build/") && !lower.contains("/generated/")
    }

    func shouldSkipProjectTreePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/.gradle/")
            || lower.contains("/.idea/")
            || lower.contains("/build/")
            || lower.contains("/generated/")
            || lower.contains("/.git/")
    }

    func relativePath(for path: String, rootPath: String) -> String? {
        guard path.hasPrefix(rootPath) else {
            return nil
        }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func fileItem(relativePath: String, selected: Bool, isDirectory: Bool) -> ProjectFileItem {
        let parts = relativePath.split(separator: "/").map(String.init)
        let name = parts.last ?? relativePath
        let depth = max(0, parts.count - 1)
        return ProjectFileItem(
            path: relativePath,
            name: name,
            depth: depth,
            symbol: isDirectory ? "folder" : symbol(for: name),
            isSelected: selected,
            isDirectory: isDirectory
        )
    }

    func isKeyProjectFile(_ relativePath: String) -> Bool {
        let lower = relativePath.lowercased()
        return lower.contains("build.gradle")
            || lower.contains("androidmanifest.xml")
            || lower.contains("mainactivity")
            || lower.contains("/res/layout/")
    }

    func symbol(for fileName: String) -> String {
        if fileName.hasSuffix(".gradle") || fileName.hasSuffix(".kts") || fileName == "libs.versions.toml" {
            return "hammer"
        }
        if fileName == "AndroidManifest.xml" {
            return "doc.badge.gearshape"
        }
        if fileName.hasSuffix(".kt") || fileName.hasSuffix(".java") {
            return "curlybraces"
        }
        if fileName.hasSuffix(".xml") {
            return "doc.richtext"
        }
        return "doc"
    }
}

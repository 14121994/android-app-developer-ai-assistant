public final class ToolRouter {
    private let catalog: AgentCatalog

    public init(catalog: AgentCatalog) {
        self.catalog = catalog
    }

    public func route(request: String) -> [ToolCapability] {
        let lower = request.lowercased()
        var selected: [String: ToolCapability] = [:]
        var order: [String] = []

        func add(_ name: String) {
            guard selected[name] == nil, let tool = catalog.tool(named: name) else {
                return
            }
            selected[name] = tool
            order.append(name)
        }

        add("Project indexer")
        add("Semantic file retriever")
        add("Patch editor")
        add("Undo journal")
        add("Secret scanner")
        add("Gradle build runner")
        add("Summary reporter")

        if DevelopmentAgent.containsAny(lower, "test", "coverage", "junit", "espresso", "instrumentation") {
            add("Unit test runner")
            add("Instrumentation test runner")
        }
        if DevelopmentAgent.containsAny(lower, "crash", "exception", "stack trace", "logcat", "anr") {
            add("Logcat analyzer")
            add("Emulator driver")
        }
        if DevelopmentAgent.containsAny(lower, "screen", "ui", "compose", "xml", "layout", "theme") {
            add("Screen generator")
            add("Screenshot inspector")
        }
        if DevelopmentAgent.containsAny(lower, "gradle", "dependency", "manifest", "permission", "sync") {
            add("Dependency editor")
            add("Manifest editor")
        }
        if DevelopmentAgent.containsAny(lower, "emulator", "device", "tap", "screenshot", "install", "launch") {
            add("Emulator driver")
            add("Screenshot inspector")
        }

        return order.compactMap { selected[$0] }
    }
}

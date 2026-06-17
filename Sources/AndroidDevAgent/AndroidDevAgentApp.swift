import AndroidDevAgentUI
import AppKit
import Darwin
import Sparkle
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var didCompleteInitialPlacement = false
    private let launchWindowSize = NSSize(width: 1280, height: 820)
    private let minimumWindowSize = NSSize(width: 980, height: 640)

    func show() {
        let window = existingOrNewWindow()
        NSApplication.shared.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        let needsLaunchPlacement = !didCompleteInitialPlacement
        if needsLaunchPlacement || !isFullyVisible(window) {
            placeWindowAtDesktopCenter(window)
        }
        window.orderFrontRegardless()
        window.makeMain()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if needsLaunchPlacement {
            didCompleteInitialPlacement = true
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.placeWindowAtDesktopCenter(window)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak window] in
                guard let self, let window else { return }
                self.placeWindowAtDesktopCenter(window)
            }
        }
    }

    private func existingOrNewWindow() -> NSWindow {
        if let window {
            return window
        }

        let hostingController = NSHostingController(rootView: AgentWorkbenchView())
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: launchWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Android Dev Agent"
        window.identifier = NSUserInterfaceItemIdentifier("AndroidDevAgentMainWindow")
        window.contentViewController = hostingController
        window.minSize = minimumWindowSize
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.sharingType = .readOnly
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.animationBehavior = .documentWindow
        window.hidesOnDeactivate = false
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.setContentSize(launchWindowSize)
        placeWindowAtDesktopCenter(window)
        self.window = window
        return window
    }

    private func placeWindowAtDesktopCenter(_ window: NSWindow) {
        guard let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first else {
            window.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let horizontalInset: CGFloat = 24
        let verticalInset: CGFloat = 24
        let maximumSize = NSSize(
            width: max(minimumWindowSize.width, visibleFrame.width - horizontalInset * 2),
            height: max(minimumWindowSize.height, visibleFrame.height - verticalInset * 2)
        )
        let frameSize = NSSize(
            width: min(max(window.frame.width, minimumWindowSize.width), maximumSize.width),
            height: min(max(window.frame.height, minimumWindowSize.height), maximumSize.height)
        )
        let origin = NSPoint(
            x: visibleFrame.minX + (visibleFrame.width - frameSize.width) / 2,
            y: visibleFrame.minY + (visibleFrame.height - frameSize.height) / 2
        )
        let centeredFrame = NSRect(origin: origin.integralPoint, size: frameSize.integralSize)
        window.setFrame(centeredFrame, display: true)
    }

    private func isFullyVisible(_ window: NSWindow) -> Bool {
        guard let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first else {
            return true
        }
        return screen.visibleFrame.insetBy(dx: -1, dy: -1).contains(window.frame)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        didCompleteInitialPlacement = false
    }
}

private extension NSPoint {
    var integralPoint: NSPoint {
        NSPoint(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: y.rounded(.toNearestOrAwayFromZero)
        )
    }
}

private extension NSSize {
    var integralSize: NSSize {
        NSSize(width: width.rounded(.toNearestOrAwayFromZero), height: height.rounded(.toNearestOrAwayFromZero))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        showMainWindowSoon()
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainWindowController.shared.show()
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        MainWindowController.shared.show()
    }

    func applicationDidUnhide(_ notification: Notification) {
        MainWindowController.shared.show()
    }

    private func showMainWindowSoon() {
        MainWindowController.shared.show()
        for delay in [0.15, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainWindowController.shared.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }
}

@main
enum AndroidDevAgentApp {
    private static var retainedDelegate: AppDelegate?

    @MainActor
    static func main() {
        if ProcessInfo.processInfo.environment["ANDROID_DEV_AGENT_COVERAGE_EXIT"] == "1" {
            AndroidDevAgentAppCoverageHarness.exercise()
            exit(0)
        }
        AndroidDevAgentLaunchReadiness.installCrashReporting()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.mainMenu = makeMainMenu()
        app.finishLaunching()
        MainWindowController.shared.show()
        app.run()
    }

    @MainActor
    private static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(MenuActionTarget.openAgentSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = MenuActionTarget.shared
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(AppUpdateController.shared.makeCheckForUpdatesMenuItem())
        let supportItem = NSMenuItem(
            title: "Open Support Folder",
            action: #selector(MenuActionTarget.openSupportFolder(_:)),
            keyEquivalent: ""
        )
        supportItem.target = MenuActionTarget.shared
        appMenu.addItem(supportItem)
        let logsItem = NSMenuItem(
            title: "Open Launch Logs",
            action: #selector(MenuActionTarget.openLaunchLogs(_:)),
            keyEquivalent: ""
        )
        logsItem.target = MenuActionTarget.shared
        appMenu.addItem(logsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Android Dev Agent",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let showItem = NSMenuItem(
            title: "Show Main Window",
            action: #selector(MenuActionTarget.showMainWindow(_:)),
            keyEquivalent: "n"
        )
        showItem.keyEquivalentModifierMask = [.command]
        showItem.target = MenuActionTarget.shared
        windowMenu.addItem(showItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        return mainMenu
    }
}

@MainActor
private final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    @objc func showMainWindow(_ sender: Any?) {
        MainWindowController.shared.show()
    }

    @objc func openAgentSettings(_ sender: Any?) {
        MainWindowController.shared.show()
        NotificationCenter.default.post(name: AndroidDevAgentNotifications.openAgentSettings, object: nil)
    }

    @objc func openSupportFolder(_ sender: Any?) {
        AndroidDevAgentLaunchReadiness.openSupportDirectory()
    }

    @objc func openLaunchLogs(_ sender: Any?) {
        AndroidDevAgentLaunchReadiness.openLogsDirectory()
    }
}

@MainActor
private final class AppUpdateController: NSObject {
    static let shared = AppUpdateController()

    private let updaterController: SPUStandardUpdaterController?

    private override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feedURL = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let publicKey = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if feedURL.isEmpty || publicKey.isEmpty {
            updaterController = nil
        } else {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }

        super.init()
    }

    func makeCheckForUpdatesMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Check for Updates...", action: nil, keyEquivalent: "")
        if let updaterController {
            item.target = updaterController
            item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        } else {
            item.target = self
            item.action = #selector(checkForUpdatesUnavailable(_:))
            item.isEnabled = false
        }
        return item
    }

    @objc private func checkForUpdatesUnavailable(_ sender: Any?) {}
}

@MainActor
private enum AndroidDevAgentAppCoverageHarness {
    static func exercise() {
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: Notification.Name("CoverageLaunch")))
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: true)
        _ = delegate.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
        _ = AndroidDevAgentUICoverageHarness.exercise()
    }
}

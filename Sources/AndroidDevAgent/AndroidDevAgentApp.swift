import AndroidDevAgentUI
import AppKit
import Darwin
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private var didCompleteInitialPlacement = false
    private let launchWindowSize = NSSize(width: 1280, height: 820)
    private let minimumWindowSize = NSSize(width: 1120, height: 700)

    func show() {
        let window = existingOrNewWindow()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        let needsLaunchPlacement = !didCompleteInitialPlacement
        if needsLaunchPlacement || !isFullyVisible(window) {
            placeWindowAtDesktopCenter(window)
        }
        window.orderFrontRegardless()
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Android Dev Agent"
        window.identifier = NSUserInterfaceItemIdentifier("AndroidDevAgentMainWindow")
        window.contentViewController = hostingController
        window.minSize = minimumWindowSize
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
        appMenu.addItem(
            withTitle: "Quit Android Dev Agent",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

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

        return mainMenu
    }
}

@MainActor
private final class MenuActionTarget: NSObject {
    static let shared = MenuActionTarget()

    @objc func showMainWindow(_ sender: Any?) {
        MainWindowController.shared.show()
    }
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

import AppKit
import ServiceManagement
import SwiftUI
import os

private let logger = Logger(subsystem: "dev.gunner.app", category: "App")

@main
@MainActor
enum GunnerMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only: no Dock icon, no app switcher entry.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = ProcessManager()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var outsideClickMonitor: Any?
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()

        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // The title (running count) resizes the status item, which can happen while
            // the popover is open. Re-anchor it, or it jumps to a stale position.
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(statusButtonFrameChanged),
                name: NSView.frameDidChangeNotification, object: button
            )
        }

        popover.behavior = .applicationDefined
        popover.animates = true
        let hosting = NSHostingController(
            rootView: RootView(manager: manager, closePopover: { [weak self] in self?.closePopover() })
        )
        // Fixed size, set before the first show. Otherwise the hosting controller
        // reports its size only after the popover is on screen, the popover grows
        // from its bottom edge, and the top slides up under the menu bar.
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        popover.contentSize = RootView.size

        observeStatus()
        manager.startOnLaunch()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        // Stop every child process (SIGTERM, then SIGKILL) before exiting.
        Task {
            await manager.stopAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Status item

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePopover()
            statusItem.menu = makeStatusMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Close when clicking anywhere outside the app. A global monitor only sees
        // other apps' events, so our own Open panel doesn't dismiss the popover.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            MainActor.assumeIsolated { self.closePopover() }
        }
    }

    @objc private func statusButtonFrameChanged() {
        guard popover.isShown, let button = statusItem.button else { return }
        popover.positioningRect = button.bounds
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    /// Menu bar title: number of running processes, plus a warning when something crashed.
    private func observeStatus() {
        withObservationTracking {
            let running = manager.runningCount
            let crashed = manager.crashedCount
            var parts: [String] = []
            if running > 0 { parts.append("\(running)") }
            if crashed > 0 { parts.append("⚠︎\(crashed)") }
            statusItem.button?.title = parts.joined(separator: " ")
            statusItem.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        } onChange: {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.observeStatus() }
            }
        }
    }

    // MARK: Menus

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        for process in manager.processes {
            let item = NSMenuItem(title: process.config.name, action: #selector(toggleProcess(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = process.id
            item.state = process.isActive ? .on : .off
            menu.addItem(item)
        }
        if !manager.processes.isEmpty {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Start All", action: #selector(startAll), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Stop All", action: #selector(stopAll), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Open Gunner", action: #selector(openPopover), keyEquivalent: "").target = self
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Gunner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// Accessory apps have no visible menu bar, but the main menu still handles
    /// key equivalents: without an Edit menu, ⌘C / ⌘V don't work in text fields.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Gunner", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Gunner", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = edit.addItem(withTitle: "Find…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        return main
    }

    @objc private func toggleProcess(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let process = manager.process(id: id) else { return }
        if process.isActive {
            Task { await process.stop() }
        } else {
            process.start()
        }
    }

    @objc private func startAll() {
        manager.processes.forEach { $0.start() }
    }

    @objc private func stopAll() {
        Task { await manager.stopAll() }
    }

    @objc private func openPopover() {
        showPopover()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            logger.error("Launch at Login failed: \(error)")
            let alert = NSAlert(error: error)
            alert.informativeText = "Launch at Login only works when Gunner runs from an app bundle (make install)."
            alert.runModal()
        }
    }
}

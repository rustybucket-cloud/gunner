import AppKit
import SwiftUI
import Testing

@testable import Gunner

/// Renders each screen to PNG for visual review. Opt-in:
/// `GUNNER_SNAPSHOT_DIR=/tmp/shots swift test --filter Snapshot`
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GUNNER_SNAPSHOT_DIR"] != nil))
struct SnapshotTests {
    @Test func renderScreens() async throws {
        let dir = URL(filePath: ProcessInfo.processInfo.environment["GUNNER_SNAPSHOT_DIR"]!)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = NSApplication.shared

        let store = ConfigStore(url: FileManager.default.temporaryDirectory.appending(components: "gunner-snap-\(UUID())", "p.json"))
        let manager = ProcessManager(store: store)
        func add(_ name: String, _ command: String, cwd: String = "~", autoRestart: Bool = false) -> ManagedProcess {
            var input = ProcessInput()
            (input.name, input.command, input.cwd, input.autoRestart) = (name, command, cwd, autoRestart)
            return manager.create(input)
        }
        let ticker = add("Dev server", #"printf '\033[1m\033[36mVITE\033[0m v8.3.5  ready in \033[1m312\033[0m ms\n\n  \033[32m➜\033[0m  Local:   \033[36mhttp://localhost:5173/\033[0m\n'; i=0; while true; do i=$((i+1)); printf '\033[2m%s\033[0m \033[32m[vite]\033[0m hmr update /src/App.tsx\n' "$(date +%T)"; [ $((i % 3)) = 0 ] && echo 'warning: unused variable `x`' >&2; sleep 0.2; done"#, cwd: "/tmp")
        let worker = add("Queue worker", "sleep 99998", cwd: "/tmp", autoRestart: true)
        let flaky = add("Tunnel", "echo connecting...; exit 1")
        _ = add("Tests (watch)", "pnpm test --watch", cwd: "~/code/web")
        ticker.start()
        worker.start()
        flaky.start()
        try await Task.sleep(for: .seconds(3))

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            try await render(RootView(manager: manager, closePopover: {}), appearance, to: dir.appending(path: "list-\(suffix).png"))
            try await render(RootView(manager: manager, closePopover: {}, initialRoute: .detail(ticker.id)), appearance, to: dir.appending(path: "detail-\(suffix).png"))
            try await render(RootView(manager: manager, closePopover: {}, initialRoute: .form(editing: nil)), appearance, to: dir.appending(path: "new-\(suffix).png"))
            try await render(RootView(manager: manager, closePopover: {}, initialRoute: .form(editing: worker.id)), appearance, to: dir.appending(path: "edit-\(suffix).png"))
        }
        try await render(RootView(manager: ProcessManager(store: ConfigStore(url: store.url.appendingPathExtension("empty"))), closePopover: {}), .aqua, to: dir.appending(path: "empty-light.png"))
        await manager.stopAll()
    }

    private func render(_ view: RootView, _ appearance: NSAppearance.Name, to url: URL) async throws {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 560), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
        window.close()
    }
}

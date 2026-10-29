import Foundation
import Testing

@testable import Gunner

@MainActor
@Suite(.serialized)
struct ProcessTests {
    let storeURL = FileManager.default.temporaryDirectory.appending(components: "gunner-tests-\(UUID())", "processes.json")
    let environment = ShellEnvironment()

    func makeManager() -> ProcessManager {
        ProcessManager(store: ConfigStore(url: storeURL), environment: environment)
    }

    func input(_ command: String, autoRestart: Bool = false) -> ProcessInput {
        var input = ProcessInput()
        input.command = command
        input.cwd = "/tmp"
        input.autoRestart = autoRestart
        return input
    }

    @Test func capturesOutputAndExitCode() async throws {
        let process = makeManager().create(input("echo hello; echo oops >&2; printf 'a\\rb\\r\\nc'; exit 3"))
        #expect(process.config.name == "echo")
        process.start()
        try await waitUntil { process.status == .crashed }
        #expect(process.lastExit == ExitInfo(code: 3))
        let lines = process.logs.lines.map(\.text)
        #expect(lines.contains("hello"))
        #expect(lines.contains("oops"))
        // \r and \r\n both split lines. (stdout and stderr interleave nondeterministically.)
        #expect(process.logs.lines.filter { $0.stream == .stdout }.map(\.text) == ["hello", "a", "b", "c"])
        #expect(process.logs.lines.first { $0.text == "oops" }?.stream == .stderr)
    }

    @Test func streamsOutputWhileRunning() async throws {
        let process = makeManager().create(input("echo first; sleep 30"))
        process.start()
        try await waitUntil { process.logs.lines.contains { $0.text == "first" } }
        #expect(process.status == .running)
        await process.stop()
    }

    @Test func usesLoginShellPath() async throws {
        let process = makeManager().create(input("echo $PATH"))
        process.start()
        try await waitUntil { process.status == .exited }
        let path = process.logs.lines.first { $0.stream == .stdout }?.text ?? ""
        // Something from a shell profile, beyond the bare launchd PATH.
        #expect(path.split(separator: ":").count > 4, "PATH was \(path)")
    }

    @Test func stopKillsTheWholeProcessGroup() async throws {
        let process = makeManager().create(input("sleep 7171 & sleep 7272; wait"))
        process.start()
        try await waitUntil { isRunning("sleep 7171") && isRunning("sleep 7272") }
        await process.stop()
        #expect(process.status == .stopped)
        try await waitUntil { !isRunning("sleep 7171") && !isRunning("sleep 7272") }
    }

    @Test func escalatesToSigkill() async throws {
        let process = makeManager().create(input("trap '' TERM; sleep 7373"))
        process.start()
        try await waitUntil { isRunning("sleep 7373") }
        let clock = ContinuousClock()
        let elapsed = await clock.measure { await process.stop() }
        #expect(elapsed >= .seconds(5) && elapsed < .seconds(7))
        #expect(process.logs.lines.contains { $0.text.contains("SIGKILL") })
        #expect(!isRunning("sleep 7373"))
    }

    @Test func autoRestartsWithBackoff() async throws {
        let process = makeManager().create(input("echo run; exit 1", autoRestart: true))
        process.start()
        try await waitUntil(timeout: .seconds(10)) { process.logs.lines.count { $0.text == "run" } == 3 }
        // Waits 1s, then 2s, between runs.
        let runs = process.logs.lines.filter { $0.text == "run" }.map(\.date)
        let gaps = zip(runs.dropFirst(), runs).map { $0.timeIntervalSince($1) }
        #expect(abs(gaps[0] - 1) < 0.3 && abs(gaps[1] - 2) < 0.3, "gaps: \(gaps)")
        #expect((2...3).contains(process.restarts)) // The third run may already have exited.
        #expect(process.status == .running || process.status == .restarting)
        await process.stop()
        #expect(process.status == .stopped)
    }

    @Test func reportsMissingWorkingDirectory() async throws {
        let manager = makeManager()
        var bad = input("pwd")
        bad.cwd = "/does/not/exist"
        let process = manager.create(bad)
        process.start()
        try await waitUntil { process.status == .crashed }
        #expect(process.logs.lines.first?.text == "Working directory does not exist: /does/not/exist")
    }

    @Test func restartGetsANewPid() async throws {
        let process = makeManager().create(input("sleep 7474"))
        process.start()
        try await waitUntil { process.status == .running }
        let firstPid = process.pid
        await process.restart()
        try await waitUntil { process.status == .running && process.pid != nil }
        #expect(process.pid != firstPid)
        await process.stop()
    }

    @Test func stopAllStopsEverything() async throws {
        let manager = makeManager()
        let a = manager.create(input("sleep 7575"))
        let b = manager.create(input("sleep 7676"))
        a.start()
        b.start()
        try await waitUntil { isRunning("sleep 7575") && isRunning("sleep 7676") }
        await manager.stopAll()
        #expect(a.status == .stopped && b.status == .stopped)
        #expect(!isRunning("sleep 7575") && !isRunning("sleep 7676"))
    }

    @Test func persistsConfigs() async throws {
        let manager = makeManager()
        let created = manager.create(input("pnpm dev"))
        manager.update(created, with: { var i = ProcessInput(created.config); i.name = "Web"; return i }())
        manager.create(input("pnpm test --watch"))
        let reloaded = makeManager()
        #expect(reloaded.processes.map(\.config.name) == ["Web", "pnpm"])
        await reloaded.remove(reloaded.processes[0])
        #expect(makeManager().processes.map(\.config.command) == ["pnpm test --watch"])
    }

    @Test func setsAsideCorruptConfigFile() throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[{\"bad\": 1}]".utf8).write(to: storeURL)
        #expect(makeManager().processes.isEmpty)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: storeURL.deletingLastPathComponent().path)
        #expect(siblings.contains { $0.hasPrefix("processes.json.corrupt-") })
    }

    @Test func logBufferTrimsAndClears() {
        let logs = LogBuffer()
        logs.append(.stdout, (0..<(LogBuffer.capacity + 600)).map(String.init))
        #expect(logs.lines.count == LogBuffer.capacity)
        #expect(logs.firstSequence == 600)
        #expect(logs.lines.first?.text == "600")
        logs.clear()
        #expect(logs.lines.isEmpty && logs.generation == 1 && logs.nextSequence == LogBuffer.capacity + 600)
    }
}

@Test func ansiKeepsTextAndDropsEscapes() {
    let rendered = ANSI.attributed("\u{1B}[32m✓\u{1B}[0m ready in \u{1B}[1m120ms\u{1B}[22m\u{1B}]8;;http://x\u{07}link", base: [:])
    #expect(rendered.string == "✓ ready in 120mslink")
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
}

private func isRunning(_ pattern: String) -> Bool {
    let pgrep = Process()
    pgrep.executableURL = URL(filePath: "/usr/bin/pgrep")
    pgrep.arguments = ["-f", pattern]
    pgrep.standardOutput = FileHandle.nullDevice
    try? pgrep.run()
    pgrep.waitUntilExit()
    return pgrep.terminationStatus == 0
}

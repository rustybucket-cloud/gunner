import Foundation
import Observation

/// One configured command and its live state.
///
/// While running, a supervisor task owns the child process. Cancelling that
/// task stops the child; with auto-restart on, the task restarts the child
/// with exponential backoff when it exits.
@MainActor
@Observable
final class ManagedProcess: Identifiable {
    nonisolated static let stopGracePeriod: Duration = .seconds(5)
    nonisolated static let maxRestartDelay: Double = 30
    /// A process that stays up this long is considered healthy, which resets the backoff.
    nonisolated static let healthyAfter: TimeInterval = 30

    let id: UUID
    var config: ProcessConfig
    private(set) var status: ProcessStatus = .stopped
    private(set) var pid: pid_t?
    private(set) var startedAt: Date?
    private(set) var lastExit: ExitInfo?
    private(set) var restarts = 0
    let logs = LogBuffer()

    @ObservationIgnored private let environment: ShellEnvironment
    @ObservationIgnored private var supervisor: Task<Void, Never>?

    init(config: ProcessConfig, environment: ShellEnvironment) {
        id = config.id
        self.config = config
        self.environment = environment
    }

    /// Running, or about to be: the user would press Stop, not Start.
    var isActive: Bool {
        switch status {
        case .running, .restarting, .stopping: true
        case .stopped, .exited, .crashed: false
        }
    }

    func start() {
        guard supervisor == nil else { return }
        restarts = 0
        lastExit = nil
        supervisor = Task {
            await supervise()
            supervisor = nil
        }
    }

    /// Stops the process and waits until it has exited.
    func stop() async {
        guard let supervisor else { return }
        status = .stopping
        supervisor.cancel()
        await supervisor.value
    }

    func restart() async {
        await stop()
        start()
    }

    private func supervise() async {
        var attempt = 0
        while !Task.isCancelled {
            // Read the config each time, so edits apply on the next restart.
            let config = self.config
            let startedAt = Date()
            let exit = await runOnce(config)
            if Task.isCancelled { break }

            log(exit.description)
            pid = nil
            lastExit = exit
            guard config.autoRestart else {
                status = exit.succeeded ? .exited : .crashed
                return
            }

            attempt = Date().timeIntervalSince(startedAt) > Self.healthyAfter ? 1 : attempt + 1
            let delay = min(pow(2, Double(attempt - 1)), Self.maxRestartDelay)
            log("Restarting in \(delay.formatted())s…")
            status = .restarting
            restarts += 1
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                break
            }
        }
        status = .stopped
        pid = nil
    }

    /// Spawns the command once and waits for it to exit. Cancelling kills it.
    private func runOnce(_ config: ProcessConfig) async -> ExitInfo {
        let cwd = expandTilde(config.cwd)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            log("Working directory does not exist: \(cwd)")
            return .failedToStart
        }

        let env = await environment.environment
        if Task.isCancelled { return .failedToStart }

        log("$ \(config.command)")
        let child: ChildProcess
        do {
            child = try ChildProcess.spawn(
                shell: environment.shell,
                command: config.command,
                cwd: cwd,
                environment: env,
                onOutput: { [weak self] stream, lines in
                    // The main queue is FIFO, which keeps lines in order.
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.logs.append(stream, lines) }
                    }
                }
            )
        } catch {
            log("Failed to start: \(error.localizedDescription)")
            return .failedToStart
        }

        pid = child.pid
        startedAt = Date()
        status = .running

        let exit = await withTaskCancellationHandler {
            await child.waitForExit()
        } onCancel: {
            child.terminate(gracePeriod: Self.stopGracePeriod) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.log("Did not exit after \(Self.stopGracePeriod.formatted()), sending SIGKILL")
                    }
                }
            }
        }
        // The shell is gone, but anything it left running in the background
        // is still in its process group. Clean that up too.
        child.signalGroup(SIGTERM)
        return exit
    }

    private func log(_ message: String) {
        logs.append(.system, [message])
    }
}

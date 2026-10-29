import Foundation
import Observation

/// Every configured process, in display order.
@MainActor
@Observable
final class ProcessManager {
    private(set) var processes: [ManagedProcess] = []

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let environment: ShellEnvironment

    init(store: ConfigStore = .standard, environment: ShellEnvironment = ShellEnvironment()) {
        self.store = store
        self.environment = environment
        processes = store.load().map { ManagedProcess(config: $0, environment: environment) }
    }

    var runningCount: Int { processes.count { $0.status == .running } }
    var crashedCount: Int { processes.count { $0.status == .crashed } }

    func process(id: UUID) -> ManagedProcess? {
        processes.first { $0.id == id }
    }

    @discardableResult
    func create(_ input: ProcessInput) -> ManagedProcess {
        let input = input.normalized
        let config = ProcessConfig(
            id: UUID(),
            name: input.name,
            command: input.command,
            cwd: input.cwd,
            autoRestart: input.autoRestart,
            startOnLaunch: input.startOnLaunch
        )
        let process = ManagedProcess(config: config, environment: environment)
        processes.append(process)
        persist()
        return process
    }

    /// Takes effect the next time the process starts.
    func update(_ process: ManagedProcess, with input: ProcessInput) {
        let input = input.normalized
        process.config.name = input.name
        process.config.command = input.command
        process.config.cwd = input.cwd
        process.config.autoRestart = input.autoRestart
        process.config.startOnLaunch = input.startOnLaunch
        persist()
    }

    func remove(_ process: ManagedProcess) async {
        await process.stop()
        processes.removeAll { $0 === process }
        persist()
    }

    func startOnLaunch() {
        for process in processes where process.config.startOnLaunch {
            process.start()
        }
    }

    /// Stops everything concurrently and waits until it has all exited.
    func stopAll() async {
        await withDiscardingTaskGroup { group in
            for process in processes {
                group.addTask { await process.stop() }
            }
        }
    }

    private func persist() {
        store.save(processes.map(\.config))
    }
}

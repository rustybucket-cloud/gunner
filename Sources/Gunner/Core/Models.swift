import Foundation

/// A saved process definition. Persisted to disk as JSON.
struct ProcessConfig: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var command: String
    var cwd: String
    var autoRestart: Bool
    var startOnLaunch: Bool
}

/// What the user edits in the form.
struct ProcessInput: Equatable, Sendable {
    var name = ""
    var command = ""
    var cwd = ""
    var autoRestart = true
    var startOnLaunch = false

    init() {}

    init(_ config: ProcessConfig) {
        name = config.name
        command = config.command
        cwd = config.cwd
        autoRestart = config.autoRestart
        startOnLaunch = config.startOnLaunch
    }

    /// Fills in defaults: the name falls back to the command's first word, the cwd to home.
    var normalized: ProcessInput {
        var copy = self
        copy.command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty {
            copy.name = copy.command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "Untitled"
        }
        copy.cwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.cwd.isEmpty { copy.cwd = "~" }
        return copy
    }
}

enum ProcessStatus: Sendable {
    /// Never started, or stopped by the user.
    case stopped
    case running
    case stopping
    /// Exited and waiting to be restarted.
    case restarting
    /// Exited with code 0.
    case exited
    /// Exited non-zero, was killed by a signal, or failed to start.
    case crashed

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .running: "Running"
        case .stopping: "Stopping…"
        case .restarting: "Restarting…"
        case .exited: "Exited"
        case .crashed: "Crashed"
        }
    }
}

enum LogStream: Sendable {
    case stdout, stderr, system
}

struct LogLine: Sendable {
    let date: Date
    let stream: LogStream
    let text: String
}

struct ExitInfo: Sendable, Equatable {
    /// Exit code, if the process exited normally.
    var code: Int32?
    /// Terminating signal, if the process was killed.
    var signal: Int32?

    static let failedToStart = ExitInfo(code: nil, signal: nil)

    var succeeded: Bool { code == 0 }

    var description: String {
        if let signal { return "Process terminated by \(signalName(signal))" }
        if let code { return "Process exited with code \(code)" }
        return "Process failed to start"
    }
}

func signalName(_ signal: Int32) -> String {
    let names: [Int32: String] = [
        SIGHUP: "SIGHUP", SIGINT: "SIGINT", SIGQUIT: "SIGQUIT", SIGABRT: "SIGABRT", SIGKILL: "SIGKILL",
        SIGSEGV: "SIGSEGV", SIGPIPE: "SIGPIPE", SIGTERM: "SIGTERM", SIGBUS: "SIGBUS",
    ]
    return names[signal] ?? "signal \(signal)"
}

func expandTilde(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

func abbreviateHome(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

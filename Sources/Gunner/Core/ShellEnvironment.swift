import Foundation

/// Apps launched from Finder or at login don't inherit the PATH from your shell
/// profile, so `pnpm dev` would fail with "command not found". We run the
/// user's shell once as an interactive login shell, capture its environment,
/// and use that for every process we spawn.
@MainActor
final class ShellEnvironment {
    let shell: String
    private let capture: Task<[String: String], Never>

    init(shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") {
        self.shell = shell
        capture = Task.detached { Self.capture(shell: shell) }
    }

    /// The environment for spawned commands. Waits for the capture to finish, at most a few seconds.
    var environment: [String: String] {
        get async { await capture.value }
    }

    private nonisolated static func capture(shell: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let marker = "__GUNNER_ENV__"
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(filePath: shell)
        process.arguments = ["-ilc", "printf '\(marker)'; /usr/bin/env; printf '\(marker)'"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = env.merging(["DISABLE_AUTO_UPDATE": "true"]) { $1 }

        if (try? process.run()) != nil {
            let pid = process.processIdentifier
            // A slow or broken shell profile must not block startup forever.
            let timeout = DispatchWorkItem { kill(pid, SIGKILL) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            timeout.cancel()
            process.waitUntilExit()
            let text = String(decoding: data, as: UTF8.self).components(separatedBy: marker)
            if text.count >= 3 {
                for line in text[1].split(separator: "\n") {
                    guard let eq = line.firstIndex(of: "="), eq != line.startIndex else { continue }
                    env[String(line[..<eq])] = String(line[line.index(after: eq)...])
                }
            }
        }

        // Most CLIs disable colors without a TTY; the log view renders ANSI colors.
        env["FORCE_COLOR"] = env["FORCE_COLOR"] ?? "1"
        env["CLICOLOR_FORCE"] = env["CLICOLOR_FORCE"] ?? "1"
        return env
    }
}

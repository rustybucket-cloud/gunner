import Darwin
import Foundation
import Synchronization

/// A command running under `$SHELL -c` in its own process group.
///
/// `Foundation.Process` can't put the child in a new process group, which we
/// need so that stopping `pnpm dev` also stops the node server it started.
/// So we spawn with `posix_spawn` directly.
final class ChildProcess: Sendable {
    let pid: pid_t
    private let exit = Mutex<(info: ExitInfo?, waiters: [CheckedContinuation<ExitInfo, Never>])>((nil, []))

    /// - Parameter onOutput: Called on a background thread with complete lines, in order per stream.
    static func spawn(
        shell: String,
        command: String,
        cwd: String,
        environment: [String: String],
        onOutput: @escaping @Sendable (LogStream, [String]) -> Void
    ) throws -> ChildProcess {
        let stdout = Pipe()
        let stderr = Pipe()

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, 1)
        posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, 2)
        posix_spawn_file_actions_addchdir_np(&actions, cwd)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // New process group; default signal handlers and an empty mask (GUI apps
        // ignore SIGPIPE, which children would otherwise inherit); and close every
        // file descriptor not set up above, so ours don't leak into the child.
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT)
        )
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        sigdelset(&defaultSignals, SIGKILL)
        sigdelset(&defaultSignals, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigmask(&attributes, &emptyMask)

        var pid: pid_t = 0
        let result = withCStrings([shell, "-c", command]) { argv in
            withCStrings(environment.map { "\($0.key)=\($0.value)" }) { envp in
                posix_spawn(&pid, shell, &actions, &attributes, argv, envp)
            }
        }
        // Close our copies of the write ends, so reads hit EOF when the child exits.
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: result) ?? .EIO)
        }

        let child = ChildProcess(pid: pid)
        let spawnedPID = pid
        let drained = DispatchGroup()
        for (pipe, stream) in [(stdout, LogStream.stdout), (stderr, LogStream.stderr)] {
            drained.enter()
            Thread.detachNewThread {
                readLines(from: pipe.fileHandleForReading) { onOutput(stream, $0) }
                drained.leave()
            }
        }
        Thread.detachNewThread {
            var status: Int32 = 0
            while waitpid(spawnedPID, &status, 0) == -1, errno == EINTR {}
            // Let buffered output arrive first, unless a grandchild still holds the pipes open.
            _ = drained.wait(timeout: .now() + 0.5)
            let signal = status & 0x7F
            child.finish(signal == 0 ? ExitInfo(code: (status >> 8) & 0xFF) : ExitInfo(signal: signal))
        }
        return child
    }

    private init(pid: pid_t) {
        self.pid = pid
    }

    var hasExited: Bool {
        exit.withLock { $0.info != nil }
    }

    func waitForExit() async -> ExitInfo {
        await withCheckedContinuation { continuation in
            let info = exit.withLock { state -> ExitInfo? in
                if state.info == nil { state.waiters.append(continuation) }
                return state.info
            }
            if let info { continuation.resume(returning: info) }
        }
    }

    /// Sends a signal to every process in the group.
    func signalGroup(_ signal: Int32) {
        kill(-pid, signal)
    }

    /// SIGTERM, then SIGKILL if the group is still around after `gracePeriod`.
    func terminate(gracePeriod: Duration, onEscalate: @escaping @Sendable () -> Void) {
        signalGroup(SIGTERM)
        let seconds = Double(gracePeriod.components.seconds) + Double(gracePeriod.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
            guard !hasExited else { return }
            onEscalate()
            signalGroup(SIGKILL)
        }
    }

    private func finish(_ info: ExitInfo) {
        let waiters = exit.withLock { state in
            state.info = info
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume(returning: info) }
    }
}

/// Reads until EOF, splitting on `\n`, `\r\n`, and bare `\r` (progress bars redraw with `\r`).
private func readLines(from handle: FileHandle, onLines: ([String]) -> Void) {
    defer { try? handle.close() }
    var pending = Data()
    var lastWasCR = false
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    // read(2) returns as soon as anything is available. (FileHandle.read(upToCount:)
    // waits for the full count, which would hold back a long-running process's output.)
    while true {
        let count = buffer.withUnsafeMutableBytes { read(handle.fileDescriptor, $0.baseAddress, $0.count) }
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { break }
        var lines: [String] = []
        for byte in buffer[..<count] {
            if byte == 0x0A, lastWasCR {
                lastWasCR = false
                continue
            }
            lastWasCR = byte == 0x0D
            if byte == 0x0A || byte == 0x0D {
                lines.append(String(decoding: pending, as: UTF8.self))
                pending.removeAll(keepingCapacity: true)
            } else {
                pending.append(byte)
            }
        }
        if !lines.isEmpty { onLines(lines) }
    }
    if !pending.isEmpty { onLines([String(decoding: pending, as: UTF8.self)]) }
}

private func withCStrings<R>(_ strings: [String], _ body: ([UnsafeMutablePointer<CChar>?]) -> R) -> R {
    var pointers = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.forEach { free($0) } }
    return body(pointers)
}

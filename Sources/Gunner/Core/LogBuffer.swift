import Foundation
import Observation

/// The most recent output of a process. Lines get a running sequence number so
/// the log view can append only what's new.
@MainActor
@Observable
final class LogBuffer {
    static let capacity = 5_000

    private(set) var lines: [LogLine] = []
    /// Sequence number of `lines[0]`.
    private(set) var firstSequence = 0
    /// Bumped on `clear()`, so views know to start over.
    private(set) var generation = 0

    var nextSequence: Int { firstSequence + lines.count }

    func append(_ stream: LogStream, _ texts: [String]) {
        let now = Date()
        lines.append(contentsOf: texts.map { LogLine(date: now, stream: stream, text: $0) })
        // Trim in chunks rather than on every line.
        if lines.count > Self.capacity + 500 {
            let excess = lines.count - Self.capacity
            lines.removeFirst(excess)
            firstSequence += excess
        }
    }

    func clear() {
        firstSequence = nextSequence
        lines = []
        generation += 1
    }
}

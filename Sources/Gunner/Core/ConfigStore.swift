import Foundation
import os

private let logger = Logger(subsystem: "dev.gunner.app", category: "ConfigStore")

/// Persists process definitions to `~/Library/Application Support/Gunner/processes.json`.
struct ConfigStore: Sendable {
    let url: URL

    static let standard = ConfigStore(
        url: URL.applicationSupportDirectory.appending(components: "Gunner", "processes.json")
    )

    func load() -> [ProcessConfig] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return [] // First launch.
        }
        do {
            return try JSONDecoder().decode([ProcessConfig].self, from: data)
        } catch {
            // Keep the unreadable file so the next save doesn't destroy it.
            let backup = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            logger.error("Could not read \(url.path), moving it to \(backup.path): \(error)")
            try? FileManager.default.moveItem(at: url, to: backup)
            return []
        }
    }

    func save(_ configs: [ProcessConfig]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(configs).write(to: url, options: .atomic)
        } catch {
            logger.error("Could not write \(url.path): \(error)")
        }
    }
}

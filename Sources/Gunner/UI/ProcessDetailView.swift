import SwiftUI

struct ProcessDetailView: View {
    let process: ManagedProcess
    let navigate: (Route) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Header(title: process.config.name, subtitle: AnyView(subtitle)) {
                IconButton(systemName: "chevron.left", help: "Back (Esc)") { navigate(.list) }
            } trailing: {
                IconButton(systemName: "pencil", help: "Edit") { navigate(.form(editing: process.id)) }
            }
            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(process.config.command)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text(abbreviateHome(expandTilde(process.config.cwd)) + (process.pid.map { " · pid \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()

            LogTextView(logs: process.logs, sequence: process.logs.nextSequence, generation: process.logs.generation)
                .overlay {
                    if process.logs.lines.isEmpty {
                        Text("No output yet").foregroundStyle(.secondary)
                    }
                }
            Divider()

            HStack(spacing: 8) {
                if process.isActive {
                    Button {
                        Task { await process.stop() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .disabled(process.status == .stopping)
                } else {
                    Button {
                        process.start()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                }
                Button {
                    Task { await process.restart() }
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                Spacer()
                Button {
                    process.logs.clear()
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Clear output")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var subtitle: some View {
        HStack(spacing: 6) {
            StatusDot(status: process.status)
            StatusDetail(process: process)
        }
    }
}

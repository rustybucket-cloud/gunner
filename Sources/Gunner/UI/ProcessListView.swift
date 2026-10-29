import SwiftUI

struct ProcessListView: View {
    let manager: ProcessManager
    let navigate: (Route) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "Gunner", subtitle: subtitle) {
                EmptyView()
            } trailing: {
                Button {
                    navigate(.form(editing: nil))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 26, height: 26)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("New process (⌘N)")
            }
            Divider()

            if manager.processes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(manager.processes) { process in
                            ProcessRow(process: process) { navigate(.detail(process.id)) }
                        }
                    }
                    .padding(6)
                }
            }

            Divider()
            HStack {
                Text("Right-click the menu bar icon for quick controls")
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var subtitle: AnyView? {
        guard !manager.processes.isEmpty else { return nil }
        return AnyView(Text("\(manager.runningCount) of \(manager.processes.count) running"))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("No processes yet").font(.headline)
            Text("Add a command like `pnpm dev` to keep it running in the background.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Add a Process") { navigate(.form(editing: nil)) }
                .buttonStyle(.borderedProminent)
                .padding(.top, 10)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

private struct ProcessRow: View {
    let process: ManagedProcess
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(status: process.status)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(process.config.name)
                    .fontWeight(.medium)
                Text(process.config.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    StatusDetail(process: process)
                    Text(" · \(abbreviateHome(expandTilde(process.config.cwd)))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                if process.isActive {
                    IconButton(systemName: "arrow.clockwise", help: "Restart") {
                        Task { await process.restart() }
                    }
                    IconButton(systemName: "stop.fill", help: "Stop", tint: .red) {
                        Task { await process.stop() }
                    }
                } else {
                    IconButton(systemName: "play.fill", help: "Start", tint: .green) {
                        process.start()
                    }
                }
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
    }
}

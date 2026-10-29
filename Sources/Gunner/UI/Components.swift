import SwiftUI

struct StatusDot: View {
    let status: ProcessStatus
    @State private var dimmed = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
            .background {
                if status == .running {
                    Circle().fill(status.color.opacity(0.25)).frame(width: 14, height: 14)
                }
            }
            .opacity(isTransitioning && dimmed ? 0.35 : 1)
            .animation(isTransitioning ? .easeInOut(duration: 0.8).repeatForever() : .default, value: dimmed)
            .onAppear { dimmed = true }
            .help(status.label)
    }

    private var isTransitioning: Bool {
        status == .restarting || status == .stopping
    }
}

extension ProcessStatus {
    var color: Color {
        switch self {
        case .running: .green
        case .crashed: .red
        case .restarting, .stopping: .orange
        case .stopped, .exited: .gray
        }
    }
}

/// "up 3m 12s", "exit code 1", and so on. Ticks every second while running.
struct StatusDetail: View {
    let process: ManagedProcess

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(detail(now: context.date))
                .foregroundStyle(process.status == .stopped || process.status == .exited ? .secondary : process.status.color)
        }
    }

    private func detail(now: Date) -> String {
        switch process.status {
        case .running:
            guard let startedAt = process.startedAt else { return "running" }
            return "up \(formatDuration(now.timeIntervalSince(startedAt)))"
        case .crashed, .exited:
            guard let exit = process.lastExit else { return process.status.label.lowercased() }
            if let signal = exit.signal { return "killed by \(signalName(signal))" }
            if let code = exit.code { return "exit code \(code)" }
            return "failed to start"
        case .restarting:
            return "restarting · \(process.restarts) \(process.restarts == 1 ? "restart" : "restarts")"
        case .stopped, .stopping:
            return process.status.label.lowercased()
        }
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let s = max(0, Int(interval))
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m \(s % 60)s" }
    let h = m / 60
    if h < 24 { return "\(h)h \(m % 60)m" }
    return "\(h / 24)d \(h % 24)h"
}

/// Title bar at the top of every screen.
struct Header<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: AnyView? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).lineLimit(1)
                if let subtitle {
                    subtitle.font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 50)
    }
}

struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .foregroundStyle(hovering ? (tint ?? .primary) : .secondary)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

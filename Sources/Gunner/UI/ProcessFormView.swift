import SwiftUI

struct ProcessFormView: View {
    let manager: ProcessManager
    let editing: ManagedProcess?
    let navigate: (Route) -> Void

    @State private var input: ProcessInput
    @State private var confirmingDelete = false
    @FocusState private var commandFocused: Bool

    init(manager: ProcessManager, editing: ManagedProcess?, navigate: @escaping (Route) -> Void) {
        self.manager = manager
        self.editing = editing
        self.navigate = navigate
        _input = State(initialValue: editing.map { ProcessInput($0.config) } ?? ProcessInput())
    }

    private var isValid: Bool {
        !input.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: editing == nil ? "New Process" : "Edit Process") {
                IconButton(systemName: "chevron.left", help: "Back (Esc)", action: back)
            } trailing: {
                EmptyView()
            }
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Command") {
                        TextEditor(text: $input.command)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .frame(height: 64)
                            .background(.background.opacity(0.6), in: .rect(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                            .focused($commandFocused)
                            .overlay(alignment: .topLeading) {
                                if input.command.isEmpty {
                                    Text("pnpm dev")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                        Text("Runs in your login shell, so aliases and PATH work. ⌘↩ to save.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    field("Name") {
                        TextField("Web server", text: $input.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("Working Directory") {
                        HStack {
                            TextField("~/code/my-app", text: $input.cwd)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Button("Choose…", action: chooseDirectory)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Restart automatically when it exits", isOn: $input.autoRestart)
                        Toggle("Start when Gunner launches", isOn: $input.startOnLaunch)
                    }
                    .toggleStyle(.checkbox)

                    if let editing, editing.isActive {
                        Text("Saving will restart the running process.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            }

            Divider()
            HStack(spacing: 8) {
                if let editing {
                    Button(role: .destructive) {
                        if confirmingDelete {
                            Task {
                                await manager.remove(editing)
                                navigate(.list)
                            }
                        } else {
                            confirmingDelete = true
                        }
                    } label: {
                        Label(confirmingDelete ? "Confirm Delete" : "Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                Button("Cancel", action: back)
                if editing == nil {
                    Button("Save") { save(start: false) }
                        .disabled(!isValid)
                }
                Button(editing == nil ? "Save & Start" : "Save") { save(start: editing?.isActive ?? true) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear { commandFocused = true }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.medium))
            content()
        }
    }

    private func back() {
        navigate(editing.map { .detail($0.id) } ?? .list)
    }

    private func save(start: Bool) {
        guard isValid else { return }
        if let editing {
            manager.update(editing, with: input)
            if start { Task { await editing.restart() } }
            navigate(.detail(editing.id))
        } else {
            let process = manager.create(input)
            if start { process.start() }
            navigate(.detail(process.id))
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(filePath: expandTilde(input.cwd.isEmpty ? "~" : input.cwd))
        panel.begin { response in
            if response == .OK, let url = panel.url {
                input.cwd = abbreviateHome(url.path)
            }
        }
    }
}

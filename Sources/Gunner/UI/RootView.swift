import SwiftUI

enum Route: Hashable {
    case list
    case detail(UUID)
    case form(editing: UUID?)
}

/// The popover's content. A small hand-rolled router: NavigationStack's
/// toolbar doesn't fit a popover this size.
struct RootView: View {
    let manager: ProcessManager
    let closePopover: () -> Void
    @State private var route: Route

    init(manager: ProcessManager, closePopover: @escaping () -> Void, initialRoute: Route = .list) {
        self.manager = manager
        self.closePopover = closePopover
        _route = State(initialValue: initialRoute)
    }

    var body: some View {
        Group {
            switch route {
            case .list:
                ProcessListView(manager: manager, navigate: navigate)
            case .detail(let id):
                if let process = manager.process(id: id) {
                    ProcessDetailView(process: process, navigate: navigate)
                } else {
                    ProcessListView(manager: manager, navigate: navigate)
                }
            case .form(let id):
                ProcessFormView(manager: manager, editing: id.flatMap(manager.process(id:)), navigate: navigate)
                    .id(id) // Fresh form state per process.
            }
        }
        .frame(width: 400, height: 560)
        .onExitCommand(perform: back)
        .background {
            // Hidden buttons for keyboard shortcuts.
            Button("New Process") { navigate(.form(editing: nil)) }
                .keyboardShortcut("n")
                .hidden()
        }
    }

    private func navigate(_ next: Route) {
        route = next
    }

    private func back() {
        switch route {
        case .list: closePopover()
        case .detail: route = .list
        case .form(let id?): route = .detail(id)
        case .form(nil): route = .list
        }
    }
}

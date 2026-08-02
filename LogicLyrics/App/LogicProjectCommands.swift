import SwiftUI

struct OpenLogicProjectAction {
    private let perform: @MainActor () -> Void

    init(perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }

    @MainActor
    func callAsFunction() {
        perform()
    }
}

private struct OpenLogicProjectActionKey: FocusedValueKey {
    typealias Value = OpenLogicProjectAction
}

extension FocusedValues {
    var openLogicProjectAction: OpenLogicProjectAction? {
        get { self[OpenLogicProjectActionKey.self] }
        set { self[OpenLogicProjectActionKey.self] = newValue }
    }
}

@MainActor
struct LogicProjectCommands: Commands {
    @FocusedValue(\.openLogicProjectAction) private var openLogicProjectAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.text("Open Logic Pro Project…")) {
                openLogicProjectAction?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openLogicProjectAction == nil)
        }
    }
}

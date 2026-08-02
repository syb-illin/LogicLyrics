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

struct RefreshLogicProjectAction {
    private let perform: @MainActor () -> Void

    init(perform: @escaping @MainActor () -> Void) { self.perform = perform }

    @MainActor
    func callAsFunction() { perform() }
}

private struct OpenLogicProjectActionKey: FocusedValueKey {
    typealias Value = OpenLogicProjectAction
}

private struct RefreshLogicProjectActionKey: FocusedValueKey {
    typealias Value = RefreshLogicProjectAction
}

extension FocusedValues {
    var openLogicProjectAction: OpenLogicProjectAction? {
        get { self[OpenLogicProjectActionKey.self] }
        set { self[OpenLogicProjectActionKey.self] = newValue }
    }

    var refreshLogicProjectAction: RefreshLogicProjectAction? {
        get { self[RefreshLogicProjectActionKey.self] }
        set { self[RefreshLogicProjectActionKey.self] = newValue }
    }
}

@MainActor
struct LogicProjectCommands: Commands {
    @FocusedValue(\.openLogicProjectAction) private var openLogicProjectAction
    @FocusedValue(\.refreshLogicProjectAction) private var refreshLogicProjectAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L10n.text("Open Logic Pro Project…")) {
                openLogicProjectAction?()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(openLogicProjectAction == nil)
        }
        CommandGroup(after: .newItem) {
            Button(L10n.text("Refresh Lyrics")) {
                refreshLogicProjectAction?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(refreshLogicProjectAction == nil)
        }
    }
}

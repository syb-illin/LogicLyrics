import Foundation

struct ExtractedNote: Identifiable, Hashable, Sendable {
    let id: String
    let alternative: String
    let index: Int
    let isDraft: Bool
    let sourceText: String
    var text: String

    init(alternative: String, index: Int, text: String, isDraft: Bool = false) {
        self.alternative = alternative
        self.index = index
        self.isDraft = isDraft
        id = "\(alternative)#\(index)"
        self.sourceText = text
        self.text = text
    }

    var title: String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? L10n.text("Project Notes")
    }
}

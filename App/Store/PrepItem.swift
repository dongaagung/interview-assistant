import Foundation

/// A likely interview question with a prepared answer, from the prep sheet.
struct PrepItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var category = "Custom"
    var question = ""
    /// Markdown key points, in the same style as a short-guide hint.
    var answer = ""
    /// When a real interview asked this, for questions added from a session.
    var askedAt: Date?

    static let categories = ["Opening", "Motivation", "Experience", "Technical", "Behavioral", "Logistics"]
    /// The user's own questions for the end of the interview.
    static let yourQuestionsCategory = "Your questions"

    /// Regenerating the sheet replaces what it generated, and keeps the
    /// questions real interviews asked and the user's questions for the interviewer.
    static func replacingGenerated(in items: [PrepItem], with generated: [PrepItem]) -> [PrepItem] {
        items.filter { $0.askedAt != nil || $0.category == yourQuestionsCategory } + generated
    }
}

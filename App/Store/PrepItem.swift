import Foundation

/// A likely interview question with a prepared answer, from the prep sheet.
struct PrepItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var category = "Custom"
    var question = ""
    /// Markdown key points, in the same style as a short-guide hint.
    var answer = ""

    static let categories = ["Opening", "Motivation", "Experience", "Technical", "Behavioral", "Logistics"]
}

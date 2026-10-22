import Foundation

enum Speaker: String, Codable, Sendable {
    case interviewer
    case me

    var label: String {
        switch self {
        case .interviewer: "Interviewer"
        case .me: "You"
        }
    }
}

struct TranscriptLine: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var speaker: Speaker
    var text: String
    var at: Date
}

struct SessionHint: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var question: String
    var text: String
    var at: Date
}

/// A finished live interview or practice run. Text only: raw audio is never stored.
struct Session: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case live
        case practice
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var transcript: [TranscriptLine] = []
    var hints: [SessionHint] = []
    /// Markdown feedback report, once generated.
    var feedback: String?
}

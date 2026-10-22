import Foundation

/// Instant, local first pass over one finalized interviewer segment. Clear
/// questions skip the API round trip; everything else goes to `QuestionDetector`.
enum QuestionHeuristic {
    enum Verdict: Equatable, Sendable {
        case question
        case notQuestion
        case unsure
    }

    static func classify(_ segment: String) -> Verdict {
        let text = segment.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.split { !$0.isLetter && !$0.isNumber && $0 != "'" }
        // "Can you hear me?" and "Why?" are too short to call without context.
        if words.count < 5 {
            return text.contains("?") ? .unsure : .notQuestion
        }
        if text.contains("?") { return .question }
        let lastSentence = text
            .split(whereSeparator: { ".!;".contains($0) })
            .last.map { $0.trimmingCharacters(in: .whitespaces) } ?? text
        if openers.contains(where: { lastSentence.hasPrefix($0 + " ") }) { return .question }
        if requests.contains(where: { text.contains($0) }) { return .question }
        return .unsure
    }

    private static let openers = [
        "what", "why", "how", "when", "where", "who", "which",
        "can you", "could you", "would you", "will you", "do you", "did you",
        "have you", "are you", "is there", "describe", "explain",
        // Indonesian
        "apa", "apakah", "mengapa", "kenapa", "bagaimana", "kapan", "siapa",
        "ceritakan", "jelaskan", "bisakah", "coba",
    ]

    private static let requests = [
        "tell me about", "tell us about", "walk me through", "walk us through",
        "talk me through", "give me an example", "give us an example",
        "describe a time", "share an example", "how would you", "what would you",
        "ceritakan", "jelaskan",
    ]
}

/// Asks the fast model whether an interviewer turn is a question to answer now.
struct QuestionDetector: Sendable {
    let client: any LLMClient
    let systemPrompt: String

    private struct Verdict: Decodable {
        let isQuestion: Bool
        let question: String
    }

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "is_question": ["type": "boolean"],
            "question": ["type": "string"],
        ],
        "required": ["is_question", "question"],
        "additionalProperties": false,
    ]

    func request(turn: String, context: String) -> LLMRequest {
        LLMRequest(
            purpose: .detection,
            system: systemPrompt,
            messages: [.init(role: .user, content: """
                <conversation>
                \(context)
                </conversation>

                <latest_interviewer_turn>
                \(turn)
                </latest_interviewer_turn>
                """)],
            maxTokens: 256,
            jsonSchema: Self.schema)
    }

    /// The question, restated cleanly, or nil when the turn isn't one.
    func detect(turn: String, context: String) async throws -> String? {
        let reply = try await client.complete(request(turn: turn, context: context))
        let verdict = try JSONReply.decode(Verdict.self, from: reply)
        let question = verdict.question.trimmingCharacters(in: .whitespacesAndNewlines)
        return verdict.isQuestion ? (question.isEmpty ? turn : question) : nil
    }
}

import Foundation

/// Streams an answer hint for an interviewer question: a short guide or a
/// full answer, depending on the system prompt.
///
/// Latency budget (< 2 s from question to first token): the client picks
/// its fastest settings for `.hint`, and `prewarm()` readies the prompt
/// cache and connection before the first question where the provider can.
struct HintGenerator: Sendable {
    let client: any LLMClient
    let systemPrompt: String
    var maxTokens = HintStyle.guide.maxTokens

    /// `interpretation` is the short guide's headline, when a full answer is
    /// written beside a guide: it makes both read the question the same way.
    func request(question: String, context: String, interpretation: String? = nil) -> LLMRequest {
        var content = """
            <conversation_so_far>
            \(context)
            </conversation_so_far>

            <interviewer_question>
            \(question)
            </interviewer_question>
            """
        if let interpretation {
            content += "\n\n<short_guide_headline>\n\(interpretation)\n</short_guide_headline>"
        }
        return LLMRequest(purpose: .hint, system: systemPrompt, messages: [.init(role: .user, content: content)], maxTokens: maxTokens)
    }

    func stream(question: String, context: String, interpretation: String? = nil) -> AsyncThrowingStream<String, any Error> {
        client.stream(request(question: question, context: context, interpretation: interpretation))
    }

    /// A guide's bold first line, once a newline shows it's complete, or
    /// whatever there is when the guide is `complete`.
    static func headline(in text: String, complete: Bool = false) -> String? {
        let text = text.drop(while: \.isWhitespace)
        guard let end = text.firstIndex(of: "\n") ?? (complete ? text.endIndex : nil) else { return nil }
        let line = text[..<end].replacing("**", with: "").trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : line
    }

    func prewarm() async throws {
        try await client.prewarm(request(question: "(warm-up)", context: ""))
    }
}

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

    func request(question: String, context: String) -> LLMRequest {
        LLMRequest(
            purpose: .hint,
            system: systemPrompt,
            messages: [.init(role: .user, content: """
                <conversation_so_far>
                \(context)
                </conversation_so_far>

                <interviewer_question>
                \(question)
                </interviewer_question>
                """)],
            maxTokens: maxTokens)
    }

    func stream(question: String, context: String) -> AsyncThrowingStream<String, any Error> {
        client.stream(request(question: question, context: context))
    }

    func prewarm() async throws {
        try await client.prewarm(request(question: "(warm-up)", context: ""))
    }
}

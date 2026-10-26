import Foundation

/// Translates the question on a hint card into the user's language with the
/// fast model, so a fast or accented question is understood at a glance.
struct QuestionTranslator: Sendable {
    let client: any LLMClient
    let systemPrompt: String

    init(client: any LLMClient, systemPrompt: String) {
        self.client = client
        self.systemPrompt = systemPrompt
    }

    init(client: any LLMClient, language: String) throws {
        self.init(
            client: client,
            systemPrompt: try PromptTemplate.load("translate_question").render(["language": language]))
    }

    func request(question: String) -> LLMRequest {
        LLMRequest(
            purpose: .translation,
            system: systemPrompt,
            messages: [.init(role: .user, content: question)],
            maxTokens: 300)
    }

    /// The translation, or nil when it adds nothing: the question was
    /// already in that language.
    func translate(_ question: String) async throws -> String? {
        let translation = try await client.complete(request(question: question))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty, Self.letters(translation) != Self.letters(question) else { return nil }
        return translation
    }

    private static func letters(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

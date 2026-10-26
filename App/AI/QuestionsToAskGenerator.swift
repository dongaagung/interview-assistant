import Foundation

/// Writes the questions the user asks at the end of the interview, as one
/// prep-sheet item answering "Do you have any questions for us?". The prep
/// matcher then shows them the moment the interviewer asks.
struct QuestionsToAskGenerator: Sendable {
    let client: any LLMClient
    let systemPrompt: String
    let locale: Locale

    init(client: any LLMClient, systemPrompt: String, locale: Locale) {
        self.client = client
        self.systemPrompt = systemPrompt
        self.locale = locale
    }

    init(client: any LLMClient, profile: Profile, locale: Locale) throws {
        self.init(
            client: client,
            systemPrompt: try PromptTemplate.load("questions_to_ask").render([
                "profile": PromptContext.profile(profile),
                "interview_language": PracticeSession.languageName(locale),
            ]),
            locale: locale)
    }

    /// The interviewer's question, worded so the prep matcher catches the
    /// usual ways of asking it.
    static func question(for locale: Locale) -> String {
        locale.language.languageCode == .indonesian
            ? "Apakah Anda punya pertanyaan untuk kami?" : "Do you have any questions for us?"
    }

    func request() -> LLMRequest {
        LLMRequest(
            purpose: .prep,
            system: systemPrompt,
            messages: [.init(role: .user, content: "Write my questions for the interviewer.")],
            maxTokens: 4_000)
    }

    func generate() async throws -> PrepItem {
        let answer = try await client.complete(request()).trimmingCharacters(in: .whitespacesAndNewlines)
        return PrepItem(category: PrepItem.yourQuestionsCategory, question: Self.question(for: locale), answer: answer)
    }
}

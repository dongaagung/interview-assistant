import Foundation

/// Turns a saved interview into prep-sheet items: the questions it asked,
/// restated cleanly and without repeats, with answers that build on what
/// the user said. Next time, a matching question shows its answer instantly.
struct AskedQuestionsGenerator: Sendable {
    let client: any LLMClient
    let systemPrompt: String

    init(client: any LLMClient, systemPrompt: String) {
        self.client = client
        self.systemPrompt = systemPrompt
    }

    init(client: any LLMClient, profile: Profile, stories: [StarStory], prepItems: [PrepItem]) throws {
        self.init(
            client: client,
            systemPrompt: try PromptTemplate.load("prep_from_interview").render([
                "profile": PromptContext.profile(profile),
                "star_stories": PromptContext.stories(stories),
                "prep_questions": PromptContext.prepQuestions(prepItems),
                "answer_language": PromptContext.answerLanguage(profile),
            ]))
    }

    func request(transcript: String) -> LLMRequest {
        LLMRequest(
            purpose: .prep,
            system: systemPrompt,
            messages: [.init(role: .user, content: """
                <transcript>
                \(transcript)
                </transcript>

                Write the prep-sheet entries for this interview.
                """)],
            maxTokens: 16_000,
            jsonSchema: PrepGenerator.schema)
    }

    /// Streams so a long interview can't hit the request timeout.
    func generate(from session: Session) async throws -> [PrepItem] {
        var json = ""
        for try await delta in client.stream(request(transcript: PromptContext.transcript(session.transcript))) {
            json += delta
        }
        return try PrepGenerator.decode(json).map { item in
            var item = item
            item.askedAt = session.startedAt
            return item
        }
    }
}

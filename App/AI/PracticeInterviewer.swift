import Foundation

/// The mock interviewer in Practice Mode, played by the smart model.
struct PracticeInterviewer: Sendable {
    let client: any LLMClient
    let systemPrompt: String

    func request(_ messages: [ChatMessage]) -> LLMRequest {
        LLMRequest(purpose: .practice, system: systemPrompt, messages: messages, maxTokens: 1_024)
    }

    func reply(to messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error> {
        client.stream(request(messages))
    }
}

/// Writes the post-interview feedback report with the smart model.
struct FeedbackGenerator: Sendable {
    let client: any LLMClient
    let systemPrompt: String

    init(client: any LLMClient, systemPrompt: String) {
        self.client = client
        self.systemPrompt = systemPrompt
    }

    init(client: any LLMClient, profile: Profile, stories: [StarStory]) throws {
        self.init(
            client: client,
            systemPrompt: try PromptTemplate.load("feedback").render([
                "profile": PromptContext.profile(profile),
                "star_stories": PromptContext.stories(stories),
                "answer_language": PromptContext.answerLanguage(profile),
            ]))
    }

    func request(transcript: String) -> LLMRequest {
        LLMRequest(
            purpose: .feedback,
            system: systemPrompt,
            messages: [.init(role: .user, content: """
                <transcript>
                \(transcript)
                </transcript>

                Write the feedback report for this interview.
                """)],
            maxTokens: 16_000)
    }

    func stream(transcript: String) -> AsyncThrowingStream<String, any Error> {
        client.stream(request(transcript: transcript))
    }
}

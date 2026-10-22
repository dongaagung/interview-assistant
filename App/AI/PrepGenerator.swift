import Foundation

/// Writes the prep sheet (likely questions with prepared answers) with the
/// smart model.
struct PrepGenerator: Sendable {
    let client: any LLMClient
    let systemPrompt: String

    private struct Sheet: Decodable {
        struct Item: Decodable {
            let category: String
            let question: String
            let answer: String
        }

        let items: [Item]
    }

    static let schema: JSONValue = [
        "type": "object",
        "properties": [
            "items": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "category": ["type": "string", "enum": .array(PrepItem.categories.map { .string($0) })],
                        "question": ["type": "string"],
                        "answer": ["type": "string"],
                    ],
                    "required": ["category", "question", "answer"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["items"],
        "additionalProperties": false,
    ]

    init(client: any LLMClient, systemPrompt: String) {
        self.client = client
        self.systemPrompt = systemPrompt
    }

    init(client: any LLMClient, profile: Profile, stories: [StarStory], questionCount: Int, locale: Locale) throws {
        self.init(
            client: client,
            systemPrompt: try PromptTemplate.load("prep_sheet").render([
                "profile": PromptContext.profile(profile),
                "star_stories": PromptContext.stories(stories),
                "question_count": String(questionCount),
                "interview_language": PracticeSession.languageName(locale),
                "answer_language": PromptContext.answerLanguage(profile),
            ]))
    }

    func request() -> LLMRequest {
        LLMRequest(
            purpose: .prep,
            system: systemPrompt,
            messages: [.init(role: .user, content: "Write the prep sheet.")],
            maxTokens: 16_000,
            jsonSchema: Self.schema)
    }

    /// Streams so a long generation can't hit the request timeout.
    /// `progress` gets the number of questions written so far.
    func generate(progress: @MainActor @escaping (Int) -> Void) async throws -> [PrepItem] {
        var json = ""
        for try await delta in client.stream(request()) {
            json += delta
            let count = json.components(separatedBy: "\"question\"").count - 1
            await progress(count)
        }
        return try Self.decode(json)
    }

    static func decode(_ json: String) throws -> [PrepItem] {
        try JSONReply.decode(Sheet.self, from: json).items.map {
            PrepItem(category: $0.category, question: $0.question, answer: $0.answer)
        }
    }
}

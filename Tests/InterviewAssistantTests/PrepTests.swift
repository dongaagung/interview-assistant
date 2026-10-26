import Foundation
import Testing
@testable import InterviewAssistant

struct PrepMatcherTests {
    let items = [
        PrepItem(category: "Opening", question: "Tell me about yourself.", answer: "A"),
        PrepItem(category: "Logistics", question: "What is your notice period?", answer: "B"),
        PrepItem(category: "Technical", question: "Explain Kafka and where you used it.", answer: "C"),
        PrepItem(category: "Opening", question: "Ceritakan tentang diri Anda.", answer: "D"),
        PrepItem(category: "Motivation", question: "Why do you want to leave your current job?", answer: "E"),
    ]

    @Test(arguments: [
        ("So could you start by telling me a bit about yourself?", "A"),
        ("And what's your notice period at the moment?", "B"),
        ("Coba ceritakan sedikit tentang diri anda", "D"),
    ])
    func clearRephrasingsMatch(spoken: String, answer: String) {
        #expect(PrepMatcher(items: items).match(spoken)?.answer == answer)
    }

    /// Close but different questions must get a live hint instead.
    @Test(arguments: [
        "What is Kafka and what project did you build that needed it?",
        "Tell me about yourself and why you are leaving your current job",
        "Tell me about your team at Klickers",
        "When could you start if we made an offer?",
        "Okay.",
    ])
    func lookAlikesDoNotMatch(spoken: String) {
        #expect(PrepMatcher(items: items).match(spoken) == nil)
    }
}

struct PrepSheetTests {
    @Test func promptContextListsQuestionsAndAnswers() {
        #expect(PromptContext.prepSheet([]) == "(No prepared answers.)")
        let sheet = PromptContext.prepSheet([PrepItem(question: "Q1?", answer: "**A1**\n- point")])
        #expect(sheet == "Q: Q1?\nA:\n**A1**\n- point")
    }

    @Test func requestUsesSonnetWithStructuredOutput() throws {
        let generator = PrepGenerator(client: ClaudeClient(apiKey: "k"), systemPrompt: "S")
        let data = try ClaudeClient.encoder.encode(ClaudeClient(apiKey: "k").messageRequest(for: generator.request()))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["model"] as? String == "claude-sonnet-5-5")
        #expect(json["fallbacks"] as? String == "default")
        let output = try #require(json["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "medium")
        let schema = try #require((output["format"] as? [String: Any])?["schema"] as? [String: Any])
        let item = try #require(((schema["properties"] as? [String: Any])?["items"] as? [String: Any])?["items"] as? [String: Any])
        let category = try #require((item["properties"] as? [String: Any])?["category"] as? [String: Any])
        #expect(category["enum"] as? [String] == PrepItem.categories)
    }

    @Test func decodesGeneratedSheet() throws {
        let json = #"{"items":[{"category":"Opening","question":"Tell me about yourself.","answer":"**Java backend, 6+ years.**"}]}"#
        let items = try PrepGenerator.decode(json)
        #expect(items.count == 1)
        #expect(items[0].category == "Opening")
        #expect(items[0].answer == "**Java backend, 6+ years.**")
    }

    @Test func prepQuestionsListAskedOnesFirst() {
        #expect(PromptContext.prepQuestions([]) == "(None.)")
        let items = [PrepItem(question: "Tell me about yourself."), PrepItem(question: "JDK vs JRE?", askedAt: .now)]
        #expect(PromptContext.prepQuestions(items) == "- JDK vs JRE? (asked in a real interview)\n- Tell me about yourself.")
    }

    @Test func regeneratingKeepsAskedQuestionsAndYourQuestions() {
        let generated = PrepItem(category: "Opening", question: "Tell me about yourself.", answer: "A")
        let asked = PrepItem(category: "Technical", question: "JDK vs JRE?", answer: "B", askedAt: .now)
        let yours = PrepItem(category: PrepItem.yourQuestionsCategory, question: "Do you have any questions for us?", answer: "C")
        let fresh = PrepItem(category: "Opening", question: "Introduce yourself.", answer: "D")
        #expect(PrepItem.replacingGenerated(in: [generated, asked, yours], with: [fresh]) == [asked, yours, fresh])
    }

    @Test func olderPrepItemsDecodeWithoutAskedAt() throws {
        let json = #"[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","category":"Opening","question":"Q","answer":"A"}]"#
        let items = try JSONDecoder().decode([PrepItem].self, from: Data(json.utf8))
        #expect(items.count == 1)
        #expect(items.first?.askedAt == nil)
    }

    @MainActor
    @Test func storePersistsPrepItems() {
        let files = JSONFileStore(directory: FileManager.default.temporaryDirectory.appending(path: "prep-\(UUID().uuidString)"))
        let first = AppStore(files: files, keychainPrefix: "test-\(UUID().uuidString)-")
        first.prepItems = [PrepItem(category: "Logistics", question: "Notice period?", answer: "1 month")]
        let second = AppStore(files: files, keychainPrefix: "test-\(UUID().uuidString)-")
        #expect(second.prepItems == first.prepItems)
    }
}

/// Replies with the same text to every request.
struct FixedReplyClient: LLMClient {
    let reply: String
    var providerName: String { "Fixed" }

    func stream(_ request: LLMRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(reply)
            continuation.finish()
        }
    }

    func complete(_ request: LLMRequest) async throws -> String { reply }
}

struct QuestionsToAskTests {
    let item = PrepItem(
        category: PrepItem.yourQuestionsCategory,
        question: QuestionsToAskGenerator.question(for: Locale(identifier: "en-US")), answer: "Q")

    @Test func becomesOnePrepItemInTheInterviewLanguage() async throws {
        let bullets = "- **Team** What is the team working on now?\n- **Success** What does a great first year look like?"
        let generator = QuestionsToAskGenerator(
            client: FixedReplyClient(reply: "\n\(bullets)\n"), systemPrompt: "S", locale: Locale(identifier: "en-US"))
        #expect(generator.request().purpose == .prep)
        let item = try await generator.generate()
        #expect(item.category == PrepItem.yourQuestionsCategory)
        #expect(item.question == "Do you have any questions for us?")
        #expect(item.answer == bullets)
        #expect(QuestionsToAskGenerator.question(for: Locale(identifier: "id-ID")) == "Apakah Anda punya pertanyaan untuk kami?")
    }

    @Test(arguments: ["Do you have any questions for me?", "Any questions from your side?"])
    func commonWordingsShowYourQuestionsInstantly(spoken: String) {
        #expect(PrepMatcher(items: [item]).match(spoken)?.answer == "Q")
    }

    @Test func otherAnyQuestionsGetALiveHint() {
        #expect(PrepMatcher(items: [item]).match("Do you have any experience with Kafka?") == nil)
    }
}

struct AskedQuestionsTests {
    let session = Session(
        kind: .live, title: "Bank interview", startedAt: Date(timeIntervalSince1970: 1_000),
        transcript: [
            TranscriptLine(speaker: .interviewer, text: "what is the difference between the JDK the JRE and the JVN", at: .now),
            TranscriptLine(speaker: .me, text: "The JVM runs the bytecode", at: .now),
        ])

    @Test func requestSendsTheTranscriptForAJSONSheet() {
        let request = AskedQuestionsGenerator(client: FixedReplyClient(reply: ""), systemPrompt: "S")
            .request(transcript: "Interviewer: Q")
        #expect(request.purpose == .prep)
        #expect(request.jsonSchema == PrepGenerator.schema)
        #expect(request.messages.first?.content.contains("Interviewer: Q") == true)
    }

    @Test func itemsAreMarkedAsAskedOnTheInterviewDate() async throws {
        let json = #"{"items":[{"category":"Technical","question":"What is the difference between the JDK, the JRE and the JVM?","answer":"**JDK builds, JRE runs.**"}]}"#
        let items = try await AskedQuestionsGenerator(client: FixedReplyClient(reply: json), systemPrompt: "S")
            .generate(from: session)
        #expect(items.map(\.question) == ["What is the difference between the JDK, the JRE and the JVM?"])
        #expect(items.first?.category == "Technical")
        #expect(items.first?.askedAt == session.startedAt)
    }
}

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

    @MainActor
    @Test func storePersistsPrepItems() {
        let files = JSONFileStore(directory: FileManager.default.temporaryDirectory.appending(path: "prep-\(UUID().uuidString)"))
        let first = AppStore(files: files, keychainPrefix: "test-\(UUID().uuidString)-")
        first.prepItems = [PrepItem(category: "Logistics", question: "Notice period?", answer: "1 month")]
        let second = AppStore(files: files, keychainPrefix: "test-\(UUID().uuidString)-")
        #expect(second.prepItems == first.prepItems)
    }
}

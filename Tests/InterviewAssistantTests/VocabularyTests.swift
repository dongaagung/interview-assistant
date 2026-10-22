import Testing
@testable import InterviewAssistant

struct VocabularyTests {
    @Test func extractsTechnologyNamesFromProse() {
        let text = "Led the move to Kafka and PostgreSQL on K8s. We used gRPC, Node.js and C++ e.g. for codecs. The team grew."
        let terms = InterviewVocabulary.extractTerms(from: text)
        #expect(terms == ["Kafka", "PostgreSQL", "K8s", "gRPC", "Node.js", "C++"])
    }

    @Test func extractsFromIndonesianProse() {
        let terms = InterviewVocabulary.extractTerms(from: "Saya memimpin migrasi ke Kafka di Tokopedia. Hasilnya bagus.")
        #expect(terms == ["Kafka", "Tokopedia"])
    }

    @Test func profileTermsComeFirstAndDuplicatesCollapse() {
        let profile = Profile(targetCompany: "Acme Bank", background: "Built payments on Camunda and kafka.")
        let story = StarStory(title: "Outbox rollout", action: "Added Debezium CDC", tags: ["Kafka"])
        let strings = InterviewVocabulary.contextualStrings(profile: profile, stories: [story], extra: ["OVO", "camunda"])
        #expect(Array(strings.prefix(5)) == ["Acme Bank", "Kafka", "Camunda", "Debezium", "CDC"])
        #expect(strings.contains("OVO"))
        #expect(strings.filter { $0.lowercased() == "kafka" }.count == 1)
        #expect(strings.filter { $0.lowercased() == "camunda" }.count == 1)
    }

    @Test func builtInListIsCleanAndFitsTheLimit() {
        let builtIn = InterviewVocabulary.builtIn
        #expect(InterviewVocabulary.deduplicated(builtIn).count == builtIn.count, "duplicate built-in terms")
        #expect(builtIn.count < InterviewVocabulary.limit)
        #expect(InterviewVocabulary.contextualStrings(profile: Profile(), stories: [], extra: [], limit: 10).count == 10)
    }

    @Test func commaSeparatedTermsKeepTypingFriendlyParsing() {
        #expect(" Kafka, ,Spring Boot ,".commaSeparatedItems == ["Kafka", "Spring Boot"])
    }
}

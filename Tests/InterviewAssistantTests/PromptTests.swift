import Foundation
import Testing
@testable import InterviewAssistant

struct PromptTests {
    static let promptsDirectory = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "prompts")

    @Test func rendersAndTrims() throws {
        let template = PromptTemplate(name: "t", text: "Hi {{name}}, role: {{ role }}.\n")
        #expect(template.variableNames == ["name", "role"])
        #expect(try template.render(["name": "Agung", "role": "iOS", "extra": "x"]) == "Hi Agung, role: iOS.")
    }

    @Test func missingVariableThrows() {
        let template = PromptTemplate(name: "t", text: "{{a}} {{b}}")
        #expect(throws: PromptTemplate.Failure.missingVariables(template: "t", names: ["b"])) {
            try template.render(["a": "1"])
        }
    }

    /// Each shipped template must render with exactly the variables the code supplies.
    @Test(arguments: [
        ("question_detector", []),
        ("hint", ["profile", "star_stories", "prep_sheet", "answer_language"]),
        ("hint_full", ["profile", "star_stories", "prep_sheet", "answer_language"]),
        ("prep_sheet", ["profile", "star_stories", "question_count", "interview_language", "answer_language"]),
        ("practice_interviewer", ["profile", "interview_type", "question_count", "interview_language", "prep_questions"]),
        ("feedback", ["profile", "star_stories", "answer_language"]),
        ("translate_question", ["language"]),
        ("questions_to_ask", ["profile", "interview_language"]),
        ("prep_from_interview", ["profile", "star_stories", "prep_questions", "answer_language"]),
    ] as [(String, Set<String>)])
    func shippedPromptsMatchCode(name: String, variables: Set<String>) throws {
        let template = try PromptTemplate.load(name, from: Self.promptsDirectory)
        #expect(template.variableNames == variables)
        let rendered = try template.render(Dictionary(uniqueKeysWithValues: variables.map { ($0, "VALUE") }))
        #expect(!rendered.contains("{{"))
    }

    @Test func profileAndStoriesRenderDeterministically() {
        var profile = Profile()
        #expect(PromptContext.profile(profile) == "(No profile provided.)")
        profile.name = "Agung"
        profile.targetRole = "iOS Engineer"
        #expect(PromptContext.profile(profile) == "Name: Agung\n\nTarget role: iOS Engineer")
        #expect(PromptContext.answerLanguage(profile) == "the same language the interviewer uses")

        let story = StarStory(title: "Outage", situation: "S", task: "", action: "A", result: "R", tags: ["ops"])
        #expect(PromptContext.stories([story]) == "### Outage\nSituation: S\nAction: A\nResult: R\nTags: ops")
    }

    @Test func recentTranscriptKeepsTail() {
        let lines = (1...5).map { TranscriptLine(speaker: $0.isMultiple(of: 2) ? .me : .interviewer, text: "line \($0)", at: .now) }
        #expect(PromptContext.recentTranscript(lines, maxCharacters: 40) == "You: line 4\nInterviewer: line 5")
    }
}

struct QuestionHeuristicTests {
    @Test(arguments: [
        "Tell me about a time you disagreed with your manager.",
        "So walk me through how you would design a rate limiter",
        "What made you apply for this role at our company",
        "Okay, great. Can you describe your current team's structure",
        "Ceritakan tentang proyek terbesar yang pernah kamu kerjakan",
        "How do you prioritize when everything is urgent?",
    ])
    func clearQuestions(text: String) {
        #expect(QuestionHeuristic.classify(text) == .question)
    }

    @Test(arguments: ["Okay.", "Great, thanks", "Mm-hmm.", "Right"])
    func fillersAreNotQuestions(text: String) {
        #expect(QuestionHeuristic.classify(text) == .notQuestion)
    }

    @Test(arguments: [
        "Can you hear me?",
        "Why?",
        "I lead the platform team here and we have about twenty engineers.",
    ])
    func ambiguousGoToTheModel(text: String) {
        #expect(QuestionHeuristic.classify(text) == .unsure)
    }
}

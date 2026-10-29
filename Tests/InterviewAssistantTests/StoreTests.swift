import Foundation
import Testing
@testable import InterviewAssistant

@MainActor
struct StoreTests {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "InterviewAssistantTests-\(UUID().uuidString)")

    @Test func jsonRoundTrip() throws {
        let files = JSONFileStore(directory: directory)
        let story = StarStory(title: "Migration", situation: "S", task: "T", action: "A", result: "R", tags: ["lead"])
        try files.save([story], to: "stories.json")
        #expect(try files.load([StarStory].self, from: "stories.json") == [story])
        #expect(try files.load([StarStory].self, from: "missing.json") == nil)
    }

    @Test func storePersistsAcrossLaunches() throws {
        let files = JSONFileStore(directory: directory)
        let first = AppStore(files: files, keychainPrefix: "test-\(UUID().uuidString)-")
        first.profile.name = "Agung"
        first.settings.localeIdentifier = "en-GB"
        let session = Session(
            kind: .live, title: "Acme", startedAt: Date(timeIntervalSince1970: 1_000),
            transcript: [TranscriptLine(speaker: .interviewer, text: "Hi", at: Date(timeIntervalSince1970: 1_001))])
        first.save(session)

        let second = AppStore(files: files, keychainPrefix: "test-\(UUID().uuidString)-")
        #expect(second.profile.name == "Agung")
        #expect(second.settings.localeIdentifier == "en-GB")
        #expect(second.sessions == [session])

        second.delete(session)
        #expect(AppStore(files: files, keychainPrefix: "test-\(UUID().uuidString)-").sessions.isEmpty)
    }

    @Test func olderSettingsFileKeepsDefaultsForNewFields() throws {
        let old = #"{"localeIdentifier":"id-ID","meetingAudio":{"systemWide":{}},"showsOverlay":false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(settings.localeIdentifier == "id-ID")
        #expect(settings.showsOverlay == false)
        #expect(settings.hintStyle == .guide)
        #expect(settings.readsPracticeQuestionsAloud)
        #expect(settings.textScale == TextScale.standard)
    }

    @Test func bothStyleIsTheGuideWithTheFullAnswerBesideIt() throws {
        #expect(HintStyle.allCases.map(\.label) == ["Short guide", "Full answer", "Both"])
        #expect(HintStyle.both.templateName == HintStyle.guide.templateName)
        #expect(HintStyle.both.maxTokens == HintStyle.guide.maxTokens)
        #expect(HintStyle.both.companion == .fullAnswer)
        #expect(HintStyle.guide.companion == nil)
        #expect(HintStyle.fullAnswer.companion == nil)
        var settings = AppSettings()
        settings.hintStyle = .both
        let saved = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: saved).hintStyle == .both)
    }

    @Test func sessionHintsKeepTheFullAnswerAndOlderOnesStillLoad() throws {
        let old = #"{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","question":"Q","text":"guide","at":0}"#
        #expect(try JSONDecoder().decode(SessionHint.self, from: Data(old.utf8)).fullAnswer == nil)
        let hint = SessionHint(question: "Q", text: "guide", fullAnswer: "full", at: Date(timeIntervalSince1970: 0))
        #expect(try JSONDecoder().decode(SessionHint.self, from: JSONEncoder().encode(hint)) == hint)
    }

    @Test func meetingAudioSourceCodable() throws {
        let source = MeetingAudioSource.app(bundleID: "us.zoom.xos", name: "Zoom")
        let data = try JSONEncoder().encode(source)
        #expect(try JSONDecoder().decode(MeetingAudioSource.self, from: data) == source)
    }
}

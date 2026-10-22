import AVFoundation
import Foundation
import Observation

enum InterviewType: String, CaseIterable, Identifiable, Codable, Sendable {
    case behavioral
    case technical
    case mixed
    case cultureFit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .behavioral: "Behavioral"
        case .technical: "Technical"
        case .mixed: "Mixed"
        case .cultureFit: "Culture fit"
        }
    }

    /// Fills `{{interview_type}}` in the interviewer prompt.
    var promptDescription: String {
        switch self {
        case .behavioral: "behavioral, using \"tell me about a time...\" questions about past experience"
        case .technical: "technical, about the skills and systems the role needs, without live coding"
        case .mixed: "a mix of behavioral and technical questions"
        case .cultureFit: "culture fit and motivation: why this company, ways of working, values"
        }
    }
}

/// Practice Mode: Claude Sonnet interviews, the user answers by voice (or by
/// typing), and a feedback report follows.
@MainActor
@Observable
final class PracticeSession {
    enum Phase: Equatable {
        case idle
        case preparing
        case interviewerSpeaking
        case waitingForAnswer
        case listening
        case writingFeedback
        case finished
    }

    struct Configuration {
        var interviewType: InterviewType
        var questionCount: Int
        var readsAloud: Bool
        var locale: Locale
        /// The active AI provider, or nil with `aiProblem` saying why.
        var ai: (any LLMClient)?
        var aiProblem: String?
        var profile: Profile
        var stories: [StarStory]
        var extraVocabulary: [String] = []
        var prefersTermAccuracy = false
    }

    private(set) var phase = Phase.idle
    /// Finished lines of the conversation, both speakers.
    private(set) var lines: [TranscriptLine] = []
    /// The interviewer's reply while it streams in.
    private(set) var interviewerDraft = ""
    /// The user's answer: filled by speech recognition, editable before sending.
    var answerDraft = ""
    private(set) var volatileAnswer = ""
    private(set) var questionsAsked = 0
    private(set) var questionCount = 5
    private(set) var feedback = ""
    private(set) var error: String?
    /// What preparing is doing, such as downloading the speech model.
    private(set) var preparingStatus = ""

    private var messages: [ChatMessage] = []
    private var interviewer: PracticeInterviewer?
    private var feedbackGenerator: FeedbackGenerator?
    private var interviewType = InterviewType.behavioral
    private var locale = Locale(identifier: "en-US")
    private var vocabulary: [String] = []
    private var prefersDictation = false
    private var readsAloud = true
    private var startedAt = Date.now
    private var failedStep: (() -> Void)?
    private var startTask: Task<Void, Never>?
    private var replyTask: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    private let mic = MicCapture()
    private let synthesizer = AVSpeechSynthesizer()

    var isLastQuestion: Bool { questionsAsked >= questionCount }
    var canRetry: Bool { failedStep != nil }

    /// Starts in the background so preparing can be cancelled.
    func begin(_ configuration: Configuration) {
        guard phase == .idle || phase == .finished else { return }
        startTask = Task { await start(configuration) }
    }

    private func start(_ configuration: Configuration) async {
        guard phase == .idle || phase == .finished else { return }
        reset()
        guard let client = configuration.ai else {
            error = "Practice Mode needs an AI provider. \(configuration.aiProblem ?? "Set one up in Setup.")"
            return
        }
        phase = .preparing
        preparingStatus = "Preparing speech recognition…"
        interviewType = configuration.interviewType
        questionCount = max(1, configuration.questionCount)
        readsAloud = configuration.readsAloud
        locale = configuration.locale
        vocabulary = InterviewVocabulary.contextualStrings(
            profile: configuration.profile, stories: configuration.stories,
            extra: configuration.extraVocabulary)
        prefersDictation = configuration.prefersTermAccuracy
        do {
            interviewer = PracticeInterviewer(
                client: client,
                systemPrompt: try PromptTemplate.load("practice_interviewer").render([
                    "profile": PromptContext.profile(configuration.profile),
                    "interview_type": configuration.interviewType.promptDescription,
                    "question_count": String(questionCount),
                    "interview_language": Self.languageName(locale),
                ]))
            feedbackGenerator = try FeedbackGenerator(
                client: client, profile: configuration.profile, stories: configuration.stories)
            try await SpeechAnalyzerProvider.prepare(
                locale: locale, prefersDictation: prefersDictation,
                progress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard self?.phase == .preparing else { return }
                        self?.preparingStatus = "Downloading the speech model… \(Int(fraction * 100))%"
                    }
                })
        } catch {
            guard !Task.isCancelled, phase == .preparing else { return }
            self.error = error.localizedDescription
            phase = .idle
            return
        }
        guard !Task.isCancelled, phase == .preparing else { return }
        startedAt = .now
        messages = [.init(role: .user, content: "(The candidate has joined the call. Start the interview.)")]
        askNextQuestion()
    }

    func retry() {
        let step = failedStep
        failedStep = nil
        error = nil
        step?()
    }

    // MARK: Answering

    func startAnswering() async {
        guard phase == .waitingForAnswer else { return }
        synthesizer.stopSpeaking(at: .immediate)
        error = nil
        guard await MicCapture.requestPermission() else {
            error = MicCapture.Failure.permissionDenied.localizedDescription
            return
        }
        let audio: AsyncStream<AudioChunk>
        do {
            audio = try mic.start()
        } catch {
            self.error = error.localizedDescription
            return
        }
        phase = .listening
        let speech = SpeechAnalyzerProvider(locale: locale, vocabulary: vocabulary, prefersDictation: prefersDictation)
        listener = Task { [weak self] in
            do {
                for try await update in speech.transcribe(audio) {
                    self?.apply(update)
                }
            } catch {
                if !Task.isCancelled { self?.error = error.localizedDescription }
            }
        }
    }

    func stopAnswering() async {
        guard phase == .listening else { return }
        mic.stop()
        // Let the recognizer finalize the last words, but don't hang on it.
        let listener = self.listener
        let deadline = Task {
            try? await Task.sleep(for: .seconds(3))
            listener?.cancel()
        }
        await listener?.value
        deadline.cancel()
        self.listener = nil
        if !volatileAnswer.isEmpty {
            appendToAnswer(volatileAnswer)
            volatileAnswer = ""
        }
        phase = .waitingForAnswer
    }

    /// Sends the answer. Returns the finished session after the last one.
    func submitAnswer() async -> Session? {
        if phase == .listening { await stopAnswering() }
        let answer = answerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .waitingForAnswer, !answer.isEmpty else { return nil }
        messages.append(.init(role: .user, content: answer))
        lines.append(TranscriptLine(speaker: .me, text: answer, at: .now))
        answerDraft = ""
        if isLastQuestion {
            return await finish()
        }
        askNextQuestion()
        return nil
    }

    /// Ends the interview early or after the last answer, writes feedback,
    /// and returns the session to save.
    func finish() async -> Session? {
        if phase == .listening { await stopAnswering() }
        replyTask?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        guard !lines.isEmpty, let feedbackGenerator else {
            reset()
            return nil
        }
        phase = .writingFeedback
        feedback = ""
        do {
            for try await delta in feedbackGenerator.stream(transcript: PromptContext.transcript(lines)) {
                feedback += delta
            }
        } catch {
            self.error = "Couldn't write the feedback report: \(error.localizedDescription)"
        }
        phase = .finished
        return Session(
            kind: .practice,
            title: "Practice · \(interviewType.label)",
            startedAt: startedAt,
            endedAt: .now,
            transcript: lines,
            feedback: feedback.isEmpty ? nil : feedback)
    }

    func cancel() {
        startTask?.cancel()
        replyTask?.cancel()
        listener?.cancel()
        mic.stop()
        synthesizer.stopSpeaking(at: .immediate)
        reset()
    }

    // MARK: Private

    private func askNextQuestion() {
        guard let interviewer else { return }
        phase = .interviewerSpeaking
        interviewerDraft = ""
        let messages = self.messages
        replyTask = Task { [weak self] in
            do {
                for try await delta in interviewer.reply(to: messages) {
                    self?.interviewerDraft += delta
                }
                self?.interviewerFinished()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.error = error.localizedDescription
                failedStep = { [weak self] in self?.askNextQuestion() }
            }
        }
    }

    private func interviewerFinished() {
        let reply = interviewerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        interviewerDraft = ""
        messages.append(.init(role: .assistant, content: reply))
        lines.append(TranscriptLine(speaker: .interviewer, text: reply, at: .now))
        questionsAsked += 1
        phase = .waitingForAnswer
        if readsAloud { speak(reply) }
    }

    private func apply(_ update: TranscriptUpdate) {
        if update.isFinal {
            appendToAnswer(update.text)
            volatileAnswer = ""
        } else {
            volatileAnswer = update.text
        }
    }

    private func appendToAnswer(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        answerDraft = answerDraft.isEmpty ? text : "\(answerDraft) \(text)"
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier(.bcp47))
        synthesizer.speak(utterance)
    }

    private func reset() {
        phase = .idle
        lines = []
        messages = []
        interviewerDraft = ""
        answerDraft = ""
        volatileAnswer = ""
        questionsAsked = 0
        feedback = ""
        error = nil
        failedStep = nil
    }

    nonisolated static func languageName(_ locale: Locale) -> String {
        Locale(identifier: "en").localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

import AVFoundation
import Foundation
import Observation

/// An answer hint for one interviewer turn.
struct LiveHint: Identifiable, Equatable {
    let id = UUID()
    let turnID: UUID
    var question: String
    var text = ""
    /// Unconfirmed hints are generated speculatively and stay hidden until
    /// the question detector says the turn really is a question.
    var isConfirmed: Bool
    var isStreaming = true
    var error: String?
    /// When the interviewer stopped talking, from the audio level; for a
    /// hint asked by hand, when it was asked.
    let questionEndedAt: Date
    /// When the hint was requested: at the pause, on the final text, or on a key press.
    var requestedAt = Date()
    var firstTokenAt: Date?
    /// Shown straight from the prep sheet, without an API call.
    var isPrepared = false

    /// What the user waits, from the end of the question to the first words
    /// on screen. Target: under 2 s.
    var latency: TimeInterval? {
        if isPrepared { return requestedAt.timeIntervalSince(questionEndedAt) }
        return firstTokenAt?.timeIntervalSince(questionEndedAt)
    }

    /// The part spent before the request: hearing the end of the question.
    var listeningDelay: TimeInterval { requestedAt.timeIntervalSince(questionEndedAt) }

    /// The part spent waiting for Claude's first token.
    var claudeDelay: TimeInterval? { firstTokenAt?.timeIntervalSince(requestedAt) }
}

/// Runs a live interview: captures both sides, captions them, detects
/// interviewer questions and streams answer hints.
@MainActor
@Observable
final class LiveSession {
    enum Phase: Equatable {
        case idle, starting, running, stopping
    }

    struct Configuration {
        var audioSource: MeetingAudioSource
        var locale: Locale
        /// The active AI provider, or nil with `aiProblem` saying why.
        var ai: (any LLMClient)?
        var aiProblem: String?
        var profile: Profile
        var stories: [StarStory]
        var hintStyle = HintStyle.guide
        var extraVocabulary: [String] = []
        var prefersTermAccuracy = false
        var prepItems: [PrepItem] = []
        /// Called with the session so far every few seconds while it runs,
        /// so a crash or quit loses at most a few seconds.
        var autosave: (@MainActor (Session) -> Void)?
    }

    private(set) var phase = Phase.idle
    private(set) var transcript = Transcript()
    private(set) var hints: [LiveHint] = []
    /// Problems worth telling the user about; the session may still be running.
    private(set) var warnings: [String] = []
    /// What a slow start is doing, such as downloading the speech model.
    private(set) var startupStatus: String?
    private(set) var startedAt: Date?

    var visibleHints: [LiveHint] { hints.filter(\.isConfirmed) }
    var canHint: Bool { phase == .running && hintGenerator != nil }

    static let silenceWarning = """
        No sound from the meeting yet. If the interviewer is talking, allow Interview Assistant \
        in System Settings › Privacy & Security › Screen & System Audio Recording, then start again.
        """

    private let mic = MicCapture()
    private let tap = ProcessTapCapture()
    private let hotKey = GlobalHotKey()
    private var startTask: Task<Void, Never>?
    private var listeners: [Task<Void, Never>] = []
    private var hintTask: Task<Void, Never>?
    private var detectTask: Task<Void, Never>?
    private var keepWarmTask: Task<Void, Never>?
    private var autosaveTask: Task<Void, Never>?
    private var activeHintID: LiveHint.ID?
    private var turns = TurnTracker()
    private var hintGenerator: HintGenerator?
    private var detector: QuestionDetector?
    private var prepMatcher = PrepMatcher(items: [])
    private var lastHintRequest = Date.distantPast
    private var sessionID = UUID()
    private var title = ""
    private var autosave: (@MainActor (Session) -> Void)?
    private var lastAutosaveSignature = 0
    private var capturesInterviewer = false
    private var lastInterviewerSound: Date?
    /// When the interviewer last stopped talking, from the audio level.
    private var lastInterviewerSpeechEnd: Date?

    // MARK: Lifecycle

    /// Starts in the background so the start can be cancelled while the
    /// speech model downloads.
    func begin(_ configuration: Configuration) {
        guard phase == .idle else { return }
        phase = .starting
        startTask = Task { await start(configuration) }
    }

    func cancelStart() {
        guard phase == .starting else { return }
        startTask?.cancel()
        mic.stop()
        tap.stop()
        listeners.forEach { $0.cancel() }
        listeners = []
        startupStatus = nil
        phase = .idle
    }

    private func start(_ configuration: Configuration) async {
        transcript = Transcript()
        hints = []
        warnings = []
        turns = TurnTracker()
        sessionID = UUID()
        lastAutosaveSignature = 0
        lastInterviewerSound = nil
        lastInterviewerSpeechEnd = nil
        capturesInterviewer = false
        autosave = configuration.autosave
        title = [configuration.profile.targetCompany, configuration.profile.targetRole]
            .filter { !$0.isEmpty }.joined(separator: " · ")

        prepMatcher = PrepMatcher(items: configuration.prepItems)
        setUpAI(configuration)

        startupStatus = "Preparing speech recognition…"
        do {
            // Downloads the on-device speech model on first use.
            try await SpeechAnalyzerProvider.prepare(
                locale: configuration.locale, prefersDictation: configuration.prefersTermAccuracy,
                progress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard self?.phase == .starting else { return }
                        self?.startupStatus = "Downloading the speech model… \(Int(fraction * 100))%"
                    }
                })
        } catch {
            guard !Task.isCancelled else { return }
            warn(error)
            startupStatus = nil
            phase = .idle
            return
        }
        guard !Task.isCancelled else { return }
        let speech = SpeechAnalyzerProvider(
            locale: configuration.locale,
            vocabulary: InterviewVocabulary.contextualStrings(
                profile: configuration.profile, stories: configuration.stories,
                extra: configuration.extraVocabulary),
            prefersDictation: configuration.prefersTermAccuracy)

        startupStatus = "Starting audio capture…"
        let micAllowed = await MicCapture.requestPermission()
        guard !Task.isCancelled else { return }
        if micAllowed {
            do {
                listen(to: try mic.start(), as: .me, with: speech)
            } catch {
                warn(error)
            }
        } else {
            warn(MicCapture.Failure.permissionDenied)
        }
        tap.onReattachFailure = { [weak self] error in
            self?.warn("Lost the meeting audio after the sound output changed: \(error.localizedDescription) Stop and start again.")
        }
        do {
            let audio = try tap.start(source: configuration.audioSource)
            capturesInterviewer = true
            listen(to: monitoringLevel(of: audio), as: .interviewer, with: speech)
        } catch {
            warn(error)
        }

        startupStatus = nil
        guard !listeners.isEmpty else {
            phase = .idle
            return
        }
        startedAt = .now
        phase = .running
        hotKey.register { [weak self] in self?.hintNow() }
        keepPromptCacheWarm()
        startAutosave()
    }

    /// Stops capture, waits briefly for the last captions, and returns the
    /// session to save.
    func stop() async -> Session? {
        guard phase == .running else { return nil }
        phase = .stopping
        hotKey.unregister()
        mic.stop()
        tap.stop()
        await finishListeners(within: .seconds(3))
        keepWarmTask?.cancel()
        autosaveTask?.cancel()
        detectTask?.cancel()
        hintTask?.cancel()
        hints.removeAll { !$0.isConfirmed }
        for index in hints.indices { hints[index].isStreaming = false }
        let session = snapshot(ended: true)
        phase = .idle
        return session
    }

    /// The session so far, for autosave and for saving when the app quits.
    func snapshot(ended: Bool = false) -> Session? {
        guard let startedAt, phase == .running || phase == .stopping else { return nil }
        return Session(
            id: sessionID,
            kind: .live,
            title: title.isEmpty ? "Live interview" : title,
            startedAt: startedAt,
            endedAt: ended ? .now : nil,
            transcript: transcript.lines,
            hints: hints.filter { $0.isConfirmed && !$0.text.isEmpty }
                .map { SessionHint(question: $0.question, text: $0.text, at: $0.questionEndedAt) })
    }

    // MARK: Manual hints

    /// Hints the interviewer's latest turn right away: for questions the
    /// detector missed, or to replace a hint. Bound to ⌃⌥H system-wide.
    func hintNow() {
        guard canHint else { return }
        let turn = turns.turnText.isEmpty ? transcript.lastTurn(of: .interviewer) : turns.turnText
        guard !turn.isEmpty else {
            warn("Nothing from the interviewer to hint yet. Type the question instead.")
            return
        }
        let turnID = turns.turnText.isEmpty ? UUID() : turns.turnID
        turns.confirmHint(for: turnID)
        // Asking by hand means "a live answer, please", even if the prep sheet has one.
        requestHint(for: turn, turnID: turnID, confirmed: true, questionEndedAt: .now, allowsPrepared: false)
    }

    /// Hints a question the user typed.
    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canHint, !question.isEmpty else { return }
        requestHint(for: question, turnID: UUID(), confirmed: true, questionEndedAt: .now)
    }

    // MARK: Pipeline

    private func setUpAI(_ configuration: Configuration) {
        guard let client = configuration.ai else {
            let reason = configuration.aiProblem ?? "Set up an AI provider in Setup."
            warnings.append("No hints: \(reason) Captions still work.")
            hintGenerator = nil
            detector = nil
            return
        }
        do {
            let hintPrompt = try PromptTemplate.load(configuration.hintStyle.templateName).render([
                "profile": PromptContext.profile(configuration.profile),
                "star_stories": PromptContext.stories(configuration.stories),
                "prep_sheet": PromptContext.prepSheet(configuration.prepItems),
                "answer_language": PromptContext.answerLanguage(configuration.profile),
            ])
            hintGenerator = HintGenerator(
                client: client, systemPrompt: hintPrompt, maxTokens: configuration.hintStyle.maxTokens)
            detector = QuestionDetector(
                client: client, systemPrompt: try PromptTemplate.load("question_detector").render([:]))
        } catch {
            warn(error)
        }
    }

    private func listen(to audio: AsyncStream<AudioChunk>, as speaker: Speaker, with speech: some SttProvider) {
        listeners.append(Task { [weak self] in
            do {
                for try await update in speech.transcribe(audio) {
                    self?.handle(update, from: speaker)
                }
            } catch {
                if !Task.isCancelled { self?.warn(error) }
            }
        })
    }

    /// Passes the interviewer's audio through, watching its level off the
    /// main actor: notes that the meeting isn't silent (at most every 2 s),
    /// and reports each pause that could end a question.
    private func monitoringLevel(of audio: AsyncStream<AudioChunk>) -> AsyncStream<AudioChunk> {
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self, bufferingPolicy: .bufferingNewest(128))
        let task = Task.detached { [weak self] in
            var lastHeardReport = ContinuousClock.now - .seconds(10)
            var pauses = PauseDetector()
            for await chunk in audio {
                continuation.yield(chunk)
                let peak = chunk.buffer.peakLevel
                if peak > AVAudioPCMBuffer.silenceThreshold, ContinuousClock.now - lastHeardReport > .seconds(2) {
                    lastHeardReport = .now
                    await self?.heardInterviewer()
                }
                if let speechEnd = pauses.feed(peak: peak, endingAt: Date()) {
                    await self?.interviewerPaused(speechEndedAt: speechEnd)
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// The final text for the last words is still 1 to 2 s away, but the
    /// in-progress text usually already holds the whole question.
    private func interviewerPaused(speechEndedAt end: Date) {
        lastInterviewerSpeechEnd = end
        guard phase == .running, let volatile = transcript.volatileText[.interviewer] else { return }
        if case .hint(let turn) = turns.interviewerPaused(volatile: volatile) {
            requestHint(for: turn, confirmed: true, questionEndedAt: end)
        }
    }

    private func heardInterviewer() {
        lastInterviewerSound = .now
        warnings.removeAll { $0 == Self.silenceWarning }
    }

    private func finishListeners(within timeout: Duration) async {
        let pending = listeners
        listeners = []
        let deadline = Task {
            try? await Task.sleep(for: timeout)
            pending.forEach { $0.cancel() }
        }
        for listener in pending { await listener.value }
        deadline.cancel()
    }

    private func handle(_ update: TranscriptUpdate, from speaker: Speaker) {
        let now = Date.now
        if speaker == .me, update.isFinal,
           EchoFilter.isLikelyEcho(update.text, at: now, recent: transcript.lines) {
            transcript.discardVolatile(.me)
            return
        }
        guard let line = transcript.apply(update, from: speaker, at: now) else { return }
        switch speaker {
        case .me:
            turns.candidateSaid(line.text)
        case .interviewer:
            let questionEnded = recentSpeechEnd(before: now)
            switch turns.interviewerSaid(line.text) {
            case .none: break
            case .hint(let turn): requestHint(for: turn, confirmed: true, questionEndedAt: questionEnded)
            case .hintIfConfirmed(let turn): requestHint(for: turn, confirmed: false, questionEndedAt: questionEnded)
            case .keepEarlyHint(let turn): relabelHint(of: turns.turnID, as: turn)
            }
        }
    }

    /// The pause the final text belongs to, if the interviewer paused in
    /// the last few seconds; otherwise now.
    private func recentSpeechEnd(before now: Date) -> Date {
        guard let end = lastInterviewerSpeechEnd, end <= now, now.timeIntervalSince(end) < 5 else { return now }
        return end
    }

    private func relabelHint(of turnID: UUID, as question: String) {
        guard let index = hints.lastIndex(where: { $0.turnID == turnID && !$0.isPrepared }) else { return }
        hints[index].question = question
    }

    private func requestHint(
        for turn: String, turnID: UUID? = nil, confirmed: Bool, questionEndedAt: Date, allowsPrepared: Bool = true
    ) {
        let turnID = turnID ?? turns.turnID
        if allowsPrepared, let item = prepMatcher.match(turn) {
            showPrepared(item, turnID: turnID, questionEndedAt: questionEndedAt)
            return
        }
        guard let hintGenerator else { return }
        // A turn has at most one hint: a longer version of the same turn replaces it.
        hintTask?.cancel()
        detectTask?.cancel()
        hints.removeAll { $0.turnID == turnID }

        let hint = LiveHint(turnID: turnID, question: turn, isConfirmed: confirmed, questionEndedAt: questionEndedAt)
        hints.append(hint)
        activeHintID = hint.id
        lastHintRequest = .now
        let context = PromptContext.recentTranscript(transcript.lines, maxCharacters: 3_000)

        hintTask = Task { [weak self] in
            do {
                for try await delta in hintGenerator.stream(question: turn, context: context) {
                    self?.append(delta, to: hint.id)
                }
                self?.finish(hint.id, error: nil)
            } catch {
                // Cancelled requests surface as URLError.cancelled, not CancellationError.
                self?.finish(hint.id, error: Task.isCancelled ? nil : error)
            }
        }

        guard !confirmed, let detector else { return }
        detectTask = Task { [weak self] in
            do {
                let question = try await detector.detect(turn: turn, context: context)
                self?.resolve(hint.id, turnID: turnID, question: question)
            } catch {
                guard !Task.isCancelled else { return }
                self?.warn(error)
                self?.resolve(hint.id, turnID: turnID, question: nil)
            }
        }
    }

    /// A clear match with the prep sheet is evidence enough that the turn is
    /// a question, so the prepared answer shows without the detector.
    private func showPrepared(_ item: PrepItem, turnID: UUID, questionEndedAt: Date) {
        hintTask?.cancel()
        detectTask?.cancel()
        hints.removeAll { $0.turnID == turnID }
        var hint = LiveHint(turnID: turnID, question: item.question, isConfirmed: true, questionEndedAt: questionEndedAt)
        hint.text = item.answer
        hint.isStreaming = false
        hint.isPrepared = true
        hints.append(hint)
        turns.confirmHint(for: turnID)
    }

    private func resolve(_ hintID: LiveHint.ID, turnID: UUID, question: String?) {
        guard let index = hints.firstIndex(where: { $0.id == hintID }) else { return }
        if let question {
            hints[index].isConfirmed = true
            hints[index].question = question
            turns.confirmHint(for: turnID)
        } else {
            if activeHintID == hintID { hintTask?.cancel() }
            hints.remove(at: index)
        }
    }

    private func append(_ delta: String, to hintID: LiveHint.ID) {
        guard let index = hints.firstIndex(where: { $0.id == hintID }) else { return }
        if hints[index].firstTokenAt == nil {
            hints[index].firstTokenAt = .now
        }
        hints[index].text += delta
    }

    private func finish(_ hintID: LiveHint.ID, error: (any Error)?) {
        guard let index = hints.firstIndex(where: { $0.id == hintID }) else { return }
        hints[index].isStreaming = false
        if let error, !(error is CancellationError) {
            hints[index].error = error.localizedDescription
        }
    }

    // MARK: Background work

    /// Writes the hint system prompt to the prompt cache now, and again
    /// before the 5-minute cache TTL runs out during quiet stretches, so
    /// every question gets a cache hit and a warm connection.
    private func keepPromptCacheWarm() {
        guard let hintGenerator else { return }
        keepWarmTask = Task { [weak self] in
            do {
                try await hintGenerator.prewarm()
            } catch {
                self?.warn(error)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(240))
                guard let self, !Task.isCancelled else { return }
                if Date.now.timeIntervalSince(lastHintRequest) > 200 {
                    try? await hintGenerator.prewarm()
                }
            }
        }
    }

    /// Every 10 s: saves the session if it changed, and warns if the
    /// meeting has been silent since the start.
    private func startAutosave() {
        autosaveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, !Task.isCancelled, phase == .running else { return }
                saveIfChanged()
                warnIfMeetingSilent()
            }
        }
    }

    private func saveIfChanged() {
        var signature = Hasher()
        signature.combine(transcript.lines.count)
        signature.combine(transcript.lines.last?.text)
        for hint in hints where hint.isConfirmed { signature.combine(hint.text.count) }
        let value = signature.finalize()
        guard value != lastAutosaveSignature, let session = snapshot() else { return }
        lastAutosaveSignature = value
        autosave?(session)
    }

    private func warnIfMeetingSilent() {
        guard capturesInterviewer, lastInterviewerSound == nil, let startedAt,
              Date.now.timeIntervalSince(startedAt) > 20
        else { return }
        warn(Self.silenceWarning)
    }

    private func warn(_ error: any Error) {
        warn(error.localizedDescription)
    }

    private func warn(_ message: String) {
        guard !warnings.contains(message) else { return }
        warnings.append(message)
    }
}

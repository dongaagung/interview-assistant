import Foundation

/// Captions for both speakers: finalized lines plus each speaker's
/// in-progress (volatile) text.
struct Transcript: Equatable {
    private(set) var lines: [TranscriptLine] = []
    private(set) var volatileText: [Speaker: String] = [:]

    /// Applies one recognizer update. Returns the line it finalized, if any.
    @discardableResult
    mutating func apply(_ update: TranscriptUpdate, from speaker: Speaker, at date: Date = .now) -> TranscriptLine? {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard update.isFinal else {
            volatileText[speaker] = text.isEmpty ? nil : text
            return nil
        }
        volatileText[speaker] = nil
        guard !text.isEmpty else { return nil }
        // A final that is only punctuation ("?") belongs to the speaker's last line.
        guard text.contains(where: { $0.isLetter || $0.isNumber }) else {
            if let index = lines.lastIndex(where: { $0.speaker == speaker }), index == lines.count - 1,
               lines[index].text.last.map({ !".?!".contains($0) }) ?? false {
                lines[index].text += text
            }
            return nil
        }
        let line = TranscriptLine(speaker: speaker, text: text, at: date)
        lines.append(line)
        return line
    }

    mutating func discardVolatile(_ speaker: Speaker) {
        volatileText[speaker] = nil
    }

    /// The speaker's most recent run of consecutive lines, joined, even if
    /// the other speaker has talked since.
    func lastTurn(of speaker: Speaker) -> String {
        let tail = lines.reversed().drop { $0.speaker != speaker }
        return tail.prefix { $0.speaker == speaker }.reversed().map(\.text).joined(separator: " ")
    }
}

/// Without headphones the mic also hears the interviewer through the
/// speakers. Drops "my" lines that repeat what the interviewer just said.
enum EchoFilter {
    static func isLikelyEcho(_ text: String, at date: Date, recent lines: [TranscriptLine]) -> Bool {
        let words = Self.words(text)
        guard words.count >= 4 else { return false }
        let heard = Set(lines.suffix(6)
            .filter { $0.speaker == .interviewer && abs($0.at.timeIntervalSince(date)) < 4 }
            .flatMap { Self.words($0.text) })
        guard !heard.isEmpty else { return false }
        let overlap = words.filter(heard.contains).count
        return Double(overlap) / Double(words.count) >= 0.8
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

/// Groups interviewer speech into turns (everything said since the candidate
/// last spoke) and decides when a turn needs an answer hint.
struct TurnTracker {
    enum Action: Equatable {
        case none
        /// Clearly a question: start (or restart) this turn's hint now.
        case hint(turn: String)
        /// Maybe a question: start the hint now, but show it only if the
        /// detector confirms. Running both at once keeps latency at
        /// max(detector, first token) instead of their sum.
        case hintIfConfirmed(turn: String)
        /// The final text says what the early hint already answered: keep
        /// it, and label it with the final wording.
        case keepEarlyHint(turn: String)
    }

    private(set) var turnID = UUID()
    private(set) var turnText = ""
    /// A confirmed hint exists for this turn.
    private(set) var isHinted = false
    /// The text an early hint was started from, before the final text came.
    private(set) var earlyText: String?

    static let maxTurnCharacters = 1_500
    /// Fewer words than this at a pause is usually a question still forming.
    static let minEarlyWords = 6
    /// Share of the final turn's words the early text must already contain.
    static let earlyCoverage = 0.85

    mutating func interviewerSaid(_ segment: String) -> Action {
        turnText = turnText.isEmpty ? segment : "\(turnText) \(segment)"
        if turnText.count > Self.maxTurnCharacters {
            turnText = String(turnText.suffix(Self.maxTurnCharacters))
        }
        if let earlyText {
            self.earlyText = nil
            if Self.isSameQuestion(turnText, as: earlyText) {
                isHinted = true
                return .keepEarlyHint(turn: turnText)
            }
            // The question went on after the pause, or the final text heard a
            // key word differently ("coffee" became "Kafka"): hint it again.
            return .hint(turn: turnText)
        }
        switch QuestionHeuristic.classify(segment) {
        case .question:
            isHinted = true
            return .hint(turn: turnText)
        case .unsure:
            return isHinted ? .none : .hintIfConfirmed(turn: turnText)
        case .notQuestion:
            return .none
        }
    }

    /// The interviewer went quiet with `volatile` not yet final. The final
    /// text can take 1 to 2 s more, so a clear question gets its hint now.
    mutating func interviewerPaused(volatile: String) -> Action {
        let volatile = volatile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isHinted, earlyText == nil,
              volatile.split(separator: " ").count >= Self.minEarlyWords,
              QuestionHeuristic.classify(volatile) == .question
        else { return .none }
        let candidate = turnText.isEmpty ? volatile : "\(turnText) \(volatile)"
        earlyText = candidate
        isHinted = true
        return .hint(turn: candidate)
    }

    /// The candidate answering ends the interviewer's turn. Short noises
    /// ("mm-hmm", "yeah") don't.
    mutating func candidateSaid(_ segment: String) {
        guard segment.split(separator: " ").count >= 3 else { return }
        turnID = UUID()
        turnText = ""
        isHinted = false
        earlyText = nil
    }

    mutating func confirmHint(for turn: UUID) {
        if turn == turnID { isHinted = true }
    }

    /// Whether the final text asks what the early text already did: nearly
    /// all of its words are there, and any it adds are short ("a", "it"),
    /// not a key word the early text misheard.
    static func isSameQuestion(_ final: String, as early: String) -> Bool {
        func words(_ string: String) -> [String] {
            string.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        let finalWords = words(final)
        guard !finalWords.isEmpty else { return true }
        let earlyWords = Set(words(early))
        let added = finalWords.filter { !earlyWords.contains($0) }
        let coverage = Double(finalWords.count - added.count) / Double(finalWords.count)
        return coverage >= earlyCoverage && added.allSatisfy { $0.count <= 3 }
    }
}

/// Finds where the interviewer stopped talking, from the meeting audio's
/// level. Speech recognition can't say: its final text comes 1 to 2 s later,
/// and its timestamps include the trailing silence.
struct PauseDetector {
    /// Peak level counted as speech: about -36 dBFS. Meeting apps suppress
    /// noise, so the gaps between utterances sit well below it.
    static let speechLevel: Float = 0.015
    /// Gaps between words are shorter; a question ends with a longer one.
    static let pauseLength: TimeInterval = 0.55

    /// When the last chunk loud enough to be speech ended.
    private(set) var lastSpeechEnd: Date?
    private var reported = true

    /// Feeds one chunk of audio that ended at `time`. Returns when speech
    /// ended, once, as soon as the quiet after it is long enough.
    mutating func feed(peak: Float, endingAt time: Date) -> Date? {
        if peak >= Self.speechLevel {
            lastSpeechEnd = time
            reported = false
            return nil
        }
        guard !reported, let lastSpeechEnd, time.timeIntervalSince(lastSpeechEnd) >= Self.pauseLength else {
            return nil
        }
        reported = true
        return lastSpeechEnd
    }
}

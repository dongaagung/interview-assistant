import Foundation

/// Times the candidate's current answer and counts its filler words, so a
/// long or "um"-heavy answer shows while it's still going.
struct AnswerMeter: Equatable {
    /// Past this an answer shows in orange: STAR answers run 1 to 2 minutes.
    static let longAnswer: TimeInterval = 120
    /// Fewer words isn't an answer: "yeah", "sure", or an echo of the interviewer.
    static let minWords = 3

    private(set) var startedAt: Date?
    private(set) var isRunning = false
    private(set) var fillerCount = 0
    private var wordCount = 0
    private var lastHeardAt: Date?

    /// Enough finalized words to show.
    var hasAnswer: Bool { wordCount >= Self.minWords }

    /// While running, up to now; once ended, up to the candidate's last words.
    func duration(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return (isRunning ? now : lastHeardAt ?? now).timeIntervalSince(startedAt)
    }

    /// The candidate's words are coming in, in progress or final. Starts an
    /// answer unless one is running.
    mutating func candidateSpeaking(at date: Date) {
        if !isRunning {
            self = AnswerMeter()
            startedAt = date
            isRunning = true
        }
        lastHeardAt = date
    }

    /// A finalized line from the candidate.
    mutating func candidateSaid(_ text: String, at date: Date) {
        candidateSpeaking(at: date)
        let words = Self.words(text)
        wordCount += words.count
        fillerCount += Self.fillerCount(in: words)
    }

    /// A finalized line from the interviewer. A real turn ends the answer;
    /// a reaction ("okay", "mm-hmm") doesn't. Too short to be an answer, it's dropped.
    mutating func interviewerSaid(_ text: String) {
        guard isRunning, Self.words(text).count >= Self.minWords else { return }
        if hasAnswer {
            isRunning = false
        } else {
            self = AnswerMeter()
        }
    }

    static func fillerCount(in text: String) -> Int {
        fillerCount(in: words(text))
    }

    private static func fillerCount(in words: [String]) -> Int {
        var count = 0
        for (index, word) in words.enumerated() {
            if fillerWords.contains(word) { count += 1 }
            for phrase in fillerPhrases where words[index...].starts(with: phrase) {
                // "Do you know Kafka?" asks; "and, you know, we moved" fills.
                if index > 0, phrase == ["you", "know"], askingWords.contains(words[index - 1]) { continue }
                count += 1
            }
        }
        return count
    }

    /// Apostrophes stay inside words, so "I'm" doesn't leave an "m".
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }
            .map(String.init)
    }

    /// As speech recognition writes them: SpeechTranscriber writes "uh" as
    /// "ah", Indonesian dictation writes "em" as "M", and English dictation
    /// drops "um" and "uh" altogether. "Jadi" ("so") is too often a real word to count.
    private static let fillerWords: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "ah", "ahh", "er", "erm", "hm", "hmm", "mm", "m",
        "eh", "ehm", "em", "emm", "anu",
    ]

    private static let fillerPhrases = [["you", "know"], ["apa", "namanya"]]

    private static let askingWords: Set<String> = ["do", "did", "if"]
}

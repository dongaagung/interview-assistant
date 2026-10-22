import AVFoundation
import Foundation
import Testing
@testable import InterviewAssistant

struct TranscriptTests {
    @Test func volatileThenFinal() {
        var transcript = Transcript()
        #expect(transcript.apply(.init(text: "Tell me", isFinal: false), from: .interviewer) == nil)
        #expect(transcript.volatileText[.interviewer] == "Tell me")
        let line = transcript.apply(.init(text: " Tell me about yourself. ", isFinal: true), from: .interviewer)
        #expect(line?.text == "Tell me about yourself.")
        #expect(transcript.volatileText[.interviewer] == nil)
        #expect(transcript.lines.count == 1)
    }

    @Test func punctuationOnlyFinalJoinsPreviousLine() {
        var transcript = Transcript()
        transcript.apply(.init(text: "What did you build with Kafka", isFinal: true), from: .interviewer)
        #expect(transcript.apply(.init(text: "?", isFinal: true), from: .interviewer) == nil)
        #expect(transcript.lines.map(\.text) == ["What did you build with Kafka?"])
        transcript.apply(.init(text: "?", isFinal: true), from: .interviewer)
        #expect(transcript.lines.map(\.text) == ["What did you build with Kafka?"])
    }

    @Test func emptyFinalAddsNoLine() {
        var transcript = Transcript()
        #expect(transcript.apply(.init(text: "  ", isFinal: true), from: .me) == nil)
        #expect(transcript.lines.isEmpty)
    }
}

struct EchoFilterTests {
    let now = Date()

    @Test func repeatOfInterviewerIsEcho() {
        let lines = [TranscriptLine(speaker: .interviewer, text: "Tell me about a time you led a project.", at: now)]
        #expect(EchoFilter.isLikelyEcho("tell me about a time you led", at: now.addingTimeInterval(1), recent: lines))
    }

    @Test func realAnswerIsNotEcho() {
        let lines = [TranscriptLine(speaker: .interviewer, text: "Tell me about a time you led a project.", at: now)]
        #expect(!EchoFilter.isLikelyEcho("Sure, last year I led our payments migration", at: now.addingTimeInterval(1), recent: lines))
    }

    @Test func oldInterviewerLinesDontCount() {
        let lines = [TranscriptLine(speaker: .interviewer, text: "Tell me about a time you led a project.", at: now)]
        #expect(!EchoFilter.isLikelyEcho("tell me about a time you led", at: now.addingTimeInterval(30), recent: lines))
    }
}

struct TurnTrackerTests {
    @Test func clearQuestionHintsImmediatelyWithWholeTurn() {
        var turns = TurnTracker()
        #expect(turns.interviewerSaid("Thanks for joining.") == .none)
        #expect(turns.interviewerSaid("Tell me about a time you disagreed with your manager.")
            == .hint(turn: "Thanks for joining. Tell me about a time you disagreed with your manager."))
    }

    @Test func followUpInSameTurnRestartsHintWithMoreContext() {
        var turns = TurnTracker()
        _ = turns.interviewerSaid("Tell me about a conflict with a coworker.")
        let id = turns.turnID
        #expect(turns.interviewerSaid("How did you resolve it in the end?")
            == .hint(turn: "Tell me about a conflict with a coworker. How did you resolve it in the end?"))
        #expect(turns.turnID == id)
    }

    @Test func unsureSegmentsAreSpeculativeUntilConfirmed() {
        var turns = TurnTracker()
        let statement = "We are moving the whole platform to Kubernetes this year."
        #expect(turns.interviewerSaid(statement) == .hintIfConfirmed(turn: statement))
        turns.confirmHint(for: turns.turnID)
        #expect(turns.interviewerSaid("It has been quite the journey for the team.") == .none)
    }

    @Test func candidateAnswerStartsNewTurn() {
        var turns = TurnTracker()
        _ = turns.interviewerSaid("Tell me about yourself and your background.")
        let first = turns.turnID
        turns.candidateSaid("Yeah")
        #expect(turns.turnID == first)
        turns.candidateSaid("Sure, I'm an iOS engineer with six years of experience")
        #expect(turns.turnID != first)
        #expect(turns.turnText.isEmpty)
    }
}

struct AudioConverterTests {
    @Test func resamples48kStereoTo16kMono() throws {
        let source = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let target = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        var converter = AudioConverter(target: target)
        var produced: AVAudioFrameCount = 0
        for _ in 0..<10 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4_800))
            buffer.frameLength = 4_800
            for channel in 0..<2 {
                for frame in 0..<4_800 {
                    buffer.floatChannelData![channel][frame] = sinf(Float(frame) * 0.05) * 0.5
                }
            }
            let output = try converter.convert(buffer)
            #expect(output.format == target)
            produced += output.frameLength
        }
        // 1 s of 48 kHz audio is ~16,000 frames at 16 kHz, minus resampler latency.
        #expect(produced > 15_000 && produced <= 16_100)
    }

    @Test func copiedBufferIsIndependent() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        buffer.floatChannelData![0][0] = 0.25
        let copy = try #require(buffer.copied())
        buffer.floatChannelData![0][0] = 1
        #expect(copy.frameLength == 4)
        #expect(copy.floatChannelData![0][0] == 0.25)
    }
}

struct HintNowSourceTests {
    @Test func lastInterviewerTurnSurvivesTheCandidateStartingToAnswer() {
        var transcript = Transcript()
        for (speaker, text) in [(Speaker.interviewer, "Thanks for joining."), (.me, "Happy to be here, thanks."),
                                (.interviewer, "So, Kafka."), (.interviewer, "Where did you use it?"),
                                (.me, "At Bank Mandiri we used it for")] {
            transcript.apply(.init(text: text, isFinal: true), from: speaker)
        }
        #expect(transcript.lastTurn(of: .interviewer) == "So, Kafka. Where did you use it?")
        #expect(Transcript().lastTurn(of: .interviewer).isEmpty)
    }
}

struct AudioLevelTests {
    @Test func peakOfFloatAndSilence() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480
        for channel in 0..<2 { for frame in 0..<480 { buffer.floatChannelData![channel][frame] = 0 } }
        #expect(buffer.peakLevel < AVAudioPCMBuffer.silenceThreshold)
        buffer.floatChannelData![1][100] = -0.5
        #expect(buffer.peakLevel == 0.5)
    }

    @Test func peakOfInt16() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        for frame in 0..<160 { buffer.int16ChannelData![0][frame] = 0 }
        buffer.int16ChannelData![0][10] = Int16.max / 4
        #expect(abs(buffer.peakLevel - 0.25) < 0.001)
    }
}

struct EarlyHintTests {
    @Test func pauseWithClearQuestionHintsBeforeTheFinalText() {
        var turns = TurnTracker()
        #expect(turns.interviewerSaid("Thanks for joining.") == .none)
        #expect(turns.interviewerPaused(volatile: "Tell me about a time you disagreed with your manager")
            == .hint(turn: "Thanks for joining. Tell me about a time you disagreed with your manager"))
        // Another pause before the final text doesn't start a second hint.
        #expect(turns.interviewerPaused(volatile: "Tell me about a time you disagreed with your manager") == .none)
    }

    @Test func finalTextMatchingTheEarlyHintKeepsIt() {
        var turns = TurnTracker()
        _ = turns.interviewerPaused(volatile: "Can you explain what Kafka is and where you used it")
        #expect(turns.interviewerSaid("Can you explain what Kafka is, and where you used it?")
            == .keepEarlyHint(turn: "Can you explain what Kafka is, and where you used it?"))
    }

    @Test func finalTextWithAKeyWordHeardDifferentlyGetsANewHint() {
        var turns = TurnTracker()
        _ = turns.interviewerPaused(volatile: "What kind of project did you build that needed coffee?")
        let final = "What kind of project did you build that needed Kafka?"
        #expect(turns.interviewerSaid(final) == .hint(turn: final))
    }

    @Test func questionThatWentOnAfterThePauseGetsANewHint() {
        var turns = TurnTracker()
        _ = turns.interviewerPaused(volatile: "Tell me about a time you disagreed with your")
        let final = "Tell me about a time you disagreed with your manager, what the conflict was, and how you resolved it."
        #expect(turns.interviewerSaid(final) == .hint(turn: final))
    }

    @Test func shortOrUnclearTextAtAPauseWaitsForTheFinalText() {
        var turns = TurnTracker()
        #expect(turns.interviewerPaused(volatile: "Tell me about") == .none)
        #expect(turns.interviewerPaused(volatile: "We are moving the whole platform to Kubernetes this year") == .none)
    }
}

struct PauseDetectorTests {
    let start = Date(timeIntervalSince1970: 1_000)

    func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func reportsWhereSpeechEndedOnceTheQuietIsLongEnough() {
        var pauses = PauseDetector()
        #expect(pauses.feed(peak: 0, endingAt: at(0)) == nil, "no speech yet")
        #expect(pauses.feed(peak: 0.3, endingAt: at(0.1)) == nil)
        #expect(pauses.feed(peak: 0.2, endingAt: at(1.0)) == nil)
        #expect(pauses.feed(peak: 0.002, endingAt: at(1.3)) == nil, "a gap between words")
        #expect(pauses.feed(peak: 0.002, endingAt: at(1.6)) == at(1.0))
        #expect(pauses.feed(peak: 0.002, endingAt: at(2.5)) == nil, "reported once")
        #expect(pauses.feed(peak: 0.4, endingAt: at(3.0)) == nil)
        #expect(pauses.feed(peak: 0, endingAt: at(3.6)) == at(3.0))
    }
}

struct HintTimingTests {
    @Test func latencySplitsIntoListeningAndClaude() {
        let ended = Date(timeIntervalSince1970: 100)
        var hint = LiveHint(turnID: UUID(), question: "Q", isConfirmed: true, questionEndedAt: ended,
                            requestedAt: ended.addingTimeInterval(0.6))
        #expect(hint.latency == nil)
        hint.firstTokenAt = ended.addingTimeInterval(1.5)
        #expect(abs((hint.latency ?? 0) - 1.5) < 0.0001)
        #expect(abs(hint.listeningDelay - 0.6) < 0.0001)
        #expect(abs((hint.claudeDelay ?? 0) - 0.9) < 0.0001)

        var prepared = LiveHint(turnID: UUID(), question: "Q", isConfirmed: true, questionEndedAt: ended,
                                requestedAt: ended.addingTimeInterval(0.7))
        prepared.isPrepared = true
        #expect(abs((prepared.latency ?? 0) - 0.7) < 0.0001)
    }
}

import Foundation

/// A partial or final piece of recognized speech.
struct TranscriptUpdate: Equatable, Sendable {
    var text: String
    /// Final text won't change again. Volatile text is replaced by later updates.
    var isFinal: Bool
}

/// Speech-to-text engine. Each call transcribes one audio stream until the
/// stream ends, then finishes its own output.
protocol SttProvider: Sendable {
    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptUpdate, any Error>
}

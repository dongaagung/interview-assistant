import AVFoundation

/// Captures the user's microphone with AVAudioEngine.
@MainActor
final class MicCapture {
    enum Failure: LocalizedError {
        case permissionDenied
        case noInputDevice

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Microphone access is off. Turn it on in System Settings › Privacy & Security › Microphone."
            case .noInputDevice:
                "No microphone found."
            }
        }
    }

    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws -> AsyncStream<AudioChunk> {
        stop()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noInputDevice }

        let (stream, continuation) = AsyncStream.makeStream(
            of: AudioChunk.self, bufferingPolicy: .bufferingNewest(128))
        // @Sendable keeps the tap block off the main actor: it runs on the audio thread.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            if let copy = buffer.copied() {
                continuation.yield(AudioChunk(buffer: copy))
            }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            throw error
        }
        self.continuation = continuation
        return stream
    }

    func stop() {
        guard let continuation else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
        self.continuation = nil
    }
}

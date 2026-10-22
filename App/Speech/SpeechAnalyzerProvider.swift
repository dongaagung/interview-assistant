import AVFoundation
import Speech

/// On-device transcription with SpeechAnalyzer (macOS 26).
///
/// Two engines, measured on spoken tech-interview questions:
/// - SpeechTranscriber finalizes faster (0.8-1.8 s after speech ends) but
///   ignores contextual strings, so "jOOQ" comes out as "Genu".
/// - DictationTranscriber uses the vocabulary (Hibernate, jOOQ, HikariCP,
///   Debezium come out right) but finalizes 0.5-1 s later. It also covers
///   more languages, Indonesian among them.
/// SpeechTranscriber is the default; DictationTranscriber is used when the
/// language needs it or `prefersDictation` asks for it.
struct SpeechAnalyzerProvider: SttProvider {
    enum Failure: LocalizedError {
        case unsupportedLocale(String)
        case noAudioFormat
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale(let id): "Speech recognition doesn't support \(id) on this Mac."
            case .noAudioFormat: "Speech recognition has no usable audio format."
            case .conversionFailed: "Couldn't convert audio for speech recognition."
            }
        }
    }

    let locale: Locale
    /// Terms to expect, such as technologies from the candidate's profile.
    /// Only DictationTranscriber uses them.
    var vocabulary: [String] = []
    var prefersDictation = false

    /// Every language either engine supports, one entry per BCP 47 identifier.
    static func supportedLocales() async -> [Locale] {
        var byID: [String: Locale] = [:]
        for locale in await DictationTranscriber.supportedLocales + SpeechTranscriber.supportedLocales {
            byID[locale.identifier(.bcp47)] = locale
        }
        return byID.keys.sorted().compactMap { byID[$0] }
    }

    /// Downloads the on-device speech model for `locale` if it's missing,
    /// reporting the download's progress from 0 to 1.
    static func prepare(
        locale: Locale, prefersDictation: Bool = false,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        _ = try await Engine.make(locale: locale, prefersDictation: prefersDictation, progress: progress)
    }

    func transcribe(_ audio: AsyncStream<AudioChunk>) -> AsyncThrowingStream<TranscriptUpdate, any Error> {
        AsyncThrowingStream { output in
            let task = Task {
                do {
                    try await run(audio, output: output)
                    output.finish()
                } catch {
                    output.finish(throwing: error)
                }
            }
            output.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        _ audio: AsyncStream<AudioChunk>,
        output: AsyncThrowingStream<TranscriptUpdate, any Error>.Continuation
    ) async throws {
        let engine = try await Engine.make(locale: locale, prefersDictation: prefersDictation)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [engine.module]) else {
            throw Failure.noAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [engine.module])
        let (inputs, inputContinuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        if case .dictation = engine, !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = vocabulary
            try await analyzer.setContext(context)
        }
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        try await analyzer.start(inputSequence: inputs)

        let results = Task {
            try await engine.forEachResult { output.yield($0) }
        }

        // Runs until capture stops (the audio stream finishes) or we're cancelled.
        var converter = AudioConverter(target: analyzerFormat)
        for await chunk in audio {
            if let converted = try? converter.convert(chunk.buffer) {
                inputContinuation.yield(AnalyzerInput(buffer: converted))
            }
        }
        inputContinuation.finish()

        if Task.isCancelled {
            await analyzer.cancelAndFinishNow()
        } else {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        try await results.value
    }

    /// The speech module doing the recognition.
    private enum Engine: Sendable {
        case transcriber(SpeechTranscriber)
        case dictation(DictationTranscriber)

        var module: any SpeechModule {
            switch self {
            case .transcriber(let module): module
            case .dictation(let module): module
            }
        }

        static func make(
            locale: Locale, prefersDictation: Bool,
            progress: (@Sendable (Double) -> Void)? = nil
        ) async throws -> Engine {
            let transcriberLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            let dictationLocale = await DictationTranscriber.supportedLocale(equivalentTo: locale)
            let engine: Engine
            if let dictationLocale, prefersDictation || transcriberLocale == nil {
                // Punctuation matters: the question heuristic looks for "?".
                engine = .dictation(DictationTranscriber(
                    locale: dictationLocale, contentHints: [], transcriptionOptions: [.punctuation],
                    reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: []))
            } else if let transcriberLocale {
                engine = .transcriber(SpeechTranscriber(
                    locale: transcriberLocale, transcriptionOptions: [],
                    reportingOptions: [.volatileResults, .fastResults], attributeOptions: []))
            } else {
                throw Failure.unsupportedLocale(locale.identifier(.bcp47))
            }
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [engine.module]) {
                let reporter = Task {
                    while !Task.isCancelled {
                        progress?(request.progress.fractionCompleted)
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                }
                defer { reporter.cancel() }
                try await request.downloadAndInstall()
            }
            return engine
        }

        func forEachResult(_ body: (TranscriptUpdate) -> Void) async throws {
            switch self {
            case .transcriber(let module):
                for try await result in module.results {
                    body(TranscriptUpdate(text: String(result.text.characters), isFinal: result.isFinal))
                }
            case .dictation(let module):
                for try await result in module.results {
                    // Dictation sometimes doubles end punctuation ("Debezium??").
                    let text = String(result.text.characters).replacing(/([?.!])\1+/) { String($0.output.1) }
                    body(TranscriptUpdate(text: text, isFinal: result.isFinal))
                }
            }
        }
    }
}

/// Converts capture-format buffers (e.g. 48 kHz stereo float) to the format
/// the analyzer wants, keeping resampler state across calls.
struct AudioConverter {
    let target: AVAudioFormat
    private var converter: AVAudioConverter?

    init(target: AVAudioFormat) {
        self.target = target
    }

    mutating func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        if buffer.format == target { return buffer }
        if converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { throw SpeechAnalyzerProvider.Failure.conversionFailed }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw SpeechAnalyzerProvider.Failure.conversionFailed
        }
        let input = SingleUse(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if let next = input.take() {
                inputStatus.pointee = .haveData
                return next
            }
            // .noDataNow (not .endOfStream) keeps the converter usable for the next buffer.
            inputStatus.pointee = .noDataNow
            return nil
        }
        if status == .error { throw error ?? SpeechAnalyzerProvider.Failure.conversionFailed }
        return output
    }
}

/// Hands out its buffer once. The converter's input block may be called more
/// than once per `convert`, and must get the buffer only the first time.
private final class SingleUse: @unchecked Sendable {
    // Unchecked: only touched synchronously inside one AVAudioConverter.convert call.
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func take() -> AVAudioPCMBuffer? {
        defer { buffer = nil }
        return buffer
    }
}

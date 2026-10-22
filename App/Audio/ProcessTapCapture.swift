import AVFoundation
import CoreAudio

/// Captures what the meeting app plays (the interviewer) with a Core Audio
/// process tap, read through a private aggregate device.
@MainActor
final class ProcessTapCapture {
    enum Failure: LocalizedError {
        case appNotRunning(String)
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .appNotRunning(let name):
                "\(name) isn't using audio yet. Join the call first, or choose All system audio."
            case .unsupportedFormat:
                "The tapped audio has a format this app can't read."
            }
        }
    }

    /// Called when re-attaching after an output-device change fails.
    var onReattachFailure: (@MainActor (any Error) -> Void)?

    private var tapID = AudioObjectID.unknown
    private var tapUID: String?
    private var format: AVAudioFormat?
    private var aggregateID = AudioObjectID.unknown
    private var attachedOutputUID: String?
    private var ioProcID: AudioDeviceIOProcID?
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private let queue = DispatchQueue(label: "rakyat.interviewassistant.process-tap", qos: .userInteractive)

    /// The output-device properties that, when they change, leave the
    /// aggregate device clocked by a device that may be gone (AirPods
    /// connected or disconnected mid-call).
    private static let outputSelectors = [
        kAudioHardwarePropertyDefaultSystemOutputDevice,
        kAudioHardwarePropertyDefaultOutputDevice,
    ]

    /// The first start shows the system's audio-capture permission prompt.
    /// If it's denied, the tap delivers silence.
    func start(source: MeetingAudioSource) throws -> AsyncStream<AudioChunk> {
        stop()
        do {
            let description = try tapDescription(for: source)
            try checkCoreAudio(AudioHardwareCreateProcessTap(description, &tapID), "create the audio tap")
            tapUID = description.uuid.uuidString
            var streamDescription = try tapID.read(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
            guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
                throw Failure.unsupportedFormat
            }
            self.format = format
            let (stream, continuation) = AsyncStream.makeStream(
                of: AudioChunk.self, bufferingPolicy: .bufferingNewest(128))
            self.continuation = continuation
            try attachToOutputDevice()
            listenForOutputChanges()
            return stream
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        stopListeningForOutputChanges()
        detachFromOutputDevice()
        if tapID.isValid {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = .unknown
        tapUID = nil
        format = nil
        continuation?.finish()
        continuation = nil
    }

    /// Reads the tap through a private aggregate device clocked by the
    /// current output device. The stream and its continuation outlive
    /// re-attachment, so captions carry on.
    private func attachToOutputDevice() throws {
        guard let tapUID, let format, let continuation else { return }
        let outputDevice = try AudioObjectID.system.read(
            kAudioHardwarePropertyDefaultSystemOutputDevice, initial: AudioObjectID.unknown)
        let outputUID = try outputDevice.readString(kAudioDevicePropertyDeviceUID)
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Interview Assistant Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: tapUID,
            ]],
        ]
        try checkCoreAudio(
            AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID),
            "create the capture device")
        attachedOutputUID = outputUID

        // @Sendable keeps the IO block off the main actor: it runs on `queue`.
        let ioBlock: AudioDeviceIOBlock = { @Sendable _, inputData, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil),
                  let copy = buffer.copied()
            else { return }
            continuation.yield(AudioChunk(buffer: copy))
        }
        try checkCoreAudio(
            AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, queue, ioBlock),
            "attach to the capture device")
        try checkCoreAudio(AudioDeviceStart(aggregateID, ioProcID), "start capturing")
    }

    private func detachFromOutputDevice() {
        if aggregateID.isValid {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        ioProcID = nil
        aggregateID = .unknown
        attachedOutputUID = nil
    }

    private func listenForOutputChanges() {
        let listener: AudioObjectPropertyListenerBlock = { @Sendable [weak self] _, _ in
            // Registered on the main queue.
            MainActor.assumeIsolated { self?.outputDeviceChanged() }
        }
        for selector in Self.outputSelectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(.system, &address, .main, listener)
        }
        outputListener = listener
    }

    private func stopListeningForOutputChanges() {
        guard let outputListener else { return }
        for selector in Self.outputSelectors {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(.system, &address, .main, outputListener)
        }
        self.outputListener = nil
    }

    private func outputDeviceChanged() {
        guard continuation != nil else { return }
        let newUID = try? AudioObjectID.system
            .read(kAudioHardwarePropertyDefaultSystemOutputDevice, initial: AudioObjectID.unknown)
            .readString(kAudioDevicePropertyDeviceUID)
        // Both selectors usually fire for one switch; re-attach once.
        guard newUID != attachedOutputUID else { return }
        detachFromOutputDevice()
        do {
            try attachToOutputDevice()
        } catch {
            onReattachFailure?(error)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    private func tapDescription(for source: MeetingAudioSource) throws -> CATapDescription {
        let description: CATapDescription
        switch source {
        case .systemWide:
            let own = try? AudioObjectID.system.read(
                kAudioHardwarePropertyTranslatePIDToProcessObject, initial: AudioObjectID.unknown,
                qualifier: UInt32(bitPattern: getpid()))
            let excluded = own.map { $0.isValid ? [$0] : [] } ?? []
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        case .app(let bundleID, let name):
            let processes = AudioProcessList.current()
                .filter { $0.appBundleID == bundleID || $0.bundleID == bundleID }
                .map(\.objectID)
            guard !processes.isEmpty else { throw Failure.appNotRunning(name) }
            description = CATapDescription(stereoMixdownOfProcesses: processes)
        }
        description.uuid = UUID()
        description.name = "Interview Assistant"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        return description
    }
}

import SwiftUI

/// Start and stop a live interview; captions on the left, hints on the right.
struct LiveView: View {
    @Environment(AppStore.self) private var store
    @Environment(LiveSession.self) private var live
    @ViewState private var apps: [AudioApp] = []
    @ViewState private var typedQuestion = ""

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Interviewer audio", selection: $store.settings.meetingAudio) {
                    Text(MeetingAudioSource.systemWide.label).tag(MeetingAudioSource.systemWide)
                    Divider()
                    ForEach(sourceOptions, id: \.self) { source in
                        Text(source.label).tag(source)
                    }
                }
                .frame(maxWidth: 320)
                .disabled(live.phase != .idle)
                Button {
                    apps = AudioProcessList.apps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh the list of apps using audio")
                .disabled(live.phase != .idle)
                Picker("Hints", selection: $store.settings.hintStyle) {
                    ForEach(HintStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(live.phase != .idle)
                Spacer()
                TextSizeControl()
                startStopButton
            }
            .padding(12)

            if let status = live.startupStatus {
                Label(status, systemImage: "arrow.down.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            ForEach(live.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Divider()
            HSplitView {
                CaptionView(transcript: live.transcript)
                    .frame(minWidth: 280)
                VStack(spacing: 0) {
                    HintView(hints: live.visibleHints)
                    Divider()
                    manualHintBar
                }
                .frame(minWidth: 320)
            }
        }
        .navigationTitle("Live interview")
        .navigationSubtitle(subtitle)
        .onAppear { apps = AudioProcessList.apps() }
    }

    /// For questions the detector missed: hint the interviewer's last turn,
    /// or type the question.
    private var manualHintBar: some View {
        HStack(spacing: 8) {
            Button {
                live.hintNow()
            } label: {
                Label("Hint now", systemImage: "sparkles")
            }
            .help("Hint the interviewer's last question (\(GlobalHotKey.label), works from any app)")
            TextField("Or type a question and press Return", text: $typedQuestion)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    live.ask(typedQuestion)
                    typedQuestion = ""
                }
            Text(GlobalHotKey.label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .disabled(!live.canHint)
    }

    /// Running apps, plus the saved choice even if that app isn't running now.
    private var sourceOptions: [MeetingAudioSource] {
        var options = apps.map { MeetingAudioSource.app(bundleID: $0.bundleID, name: $0.name) }
        if case .app = store.settings.meetingAudio, !options.contains(store.settings.meetingAudio) {
            options.insert(store.settings.meetingAudio, at: 0)
        }
        return options
    }

    private var subtitle: String {
        switch live.phase {
        case .idle: "Ready"
        case .starting: "Starting…"
        case .running: "Listening"
        case .stopping: "Finishing captions…"
        }
    }

    @ViewBuilder
    private var startStopButton: some View {
        switch live.phase {
        case .idle:
            Button {
                live.begin(configuration)
            } label: {
                Label("Start", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        case .running:
            Button {
                Task {
                    if let session = await live.stop() { store.save(session) }
                }
            } label: {
                Label("Stop", systemImage: "stop.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut("r", modifiers: [.command, .shift])
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button("Cancel") { live.cancelStart() }
                    .keyboardShortcut(.cancelAction)
            }
        case .stopping:
            ProgressView().controlSize(.small)
        }
    }

    private var configuration: LiveSession.Configuration {
        LiveSession.Configuration(
            audioSource: store.settings.meetingAudio,
            locale: Locale(identifier: store.settings.localeIdentifier),
            ai: store.aiClient(),
            aiProblem: store.aiProblem,
            profile: store.profile,
            stories: store.stories,
            hintStyle: store.settings.hintStyle,
            extraVocabulary: store.settings.extraVocabulary,
            prefersTermAccuracy: store.settings.prefersTermAccuracy,
            prepItems: store.prepItems,
            autosave: { [store] session in store.save(session) })
    }
}

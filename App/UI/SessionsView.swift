import SwiftUI

/// Saved live and practice sessions: transcript, hints and feedback.
struct SessionsView: View {
    @Environment(AppStore.self) private var store
    @ViewState private var selection: Session.ID?

    var body: some View {
        HSplitView {
            List(store.sessions, selection: $selection) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: session.kind == .live ? "waveform" : "person.2.wave.2")
                        Text(session.startedAt, format: .dateTime.day().month().hour().minute())
                        if session.endedAt == nil {
                            // Autosaved and never stopped: still running, or the app quit.
                            Text("unfinished").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            .overlay {
                if store.sessions.isEmpty {
                    Text("Live interviews and practice runs are saved here.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }

            Group {
                if let session = store.sessions.first(where: { $0.id == selection }) {
                    SessionDetail(session: session)
                        .id(session.id)
                } else {
                    Text("Select a session").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Sessions")
        .onAppear {
            if selection == nil { selection = store.sessions.first?.id }
        }
    }
}

private struct SessionDetail: View {
    @Environment(AppStore.self) private var store
    let session: Session
    @ViewState private var tab = Tab.feedback
    @ViewState private var draftFeedback = ""
    @ViewState private var isWritingFeedback = false
    @ViewState private var feedbackError: String?
    @ViewState private var confirmsDelete = false
    @ViewState private var isAddingToPrep = false
    @ViewState private var prepMessage: String?
    @ViewState private var prepError: String?
    @Environment(\.textScale) private var scale

    enum Tab: String, CaseIterable, Identifiable {
        case feedback = "Feedback"
        case hints = "Hints"
        case transcript = "Transcript"
        var id: Self { self }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                Spacer()
                if isAddingToPrep {
                    ProgressView().controlSize(.small)
                } else if let prepError {
                    Label(prepError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                } else if let prepMessage {
                    Text(prepMessage).font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await addQuestionsToPrep() }
                } label: {
                    Label("Add questions to Prep", systemImage: "text.badge.plus")
                }
                .help("Adds the questions this interview asked to your prep sheet, restated cleanly, with answers that build on yours. Next time they show instantly.")
                .disabled(isAddingToPrep || !store.isAIReady || !session.transcript.contains { $0.speaker == .interviewer })
                Button(role: .destructive) {
                    confirmsDelete = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete session")
                .confirmationDialog("Delete this session?", isPresented: $confirmsDelete) {
                    Button("Delete", role: .destructive) { store.delete(session) }
                }
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .feedback: feedback
                    case .hints: hints
                    case .transcript: transcript
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let text = session.feedback, !isWritingFeedback {
            MarkdownText(markdown: text)
        } else if isWritingFeedback {
            HStack {
                ProgressView().controlSize(.small)
                Text("Writing feedback…").foregroundStyle(.secondary)
            }
            MarkdownText(markdown: draftFeedback)
        } else {
            Text("No feedback report yet.").foregroundStyle(.secondary)
            Button("Write feedback report") {
                Task { await writeFeedback() }
            }
            .disabled(session.transcript.isEmpty || !store.isAIReady)
            if let problem = store.aiProblem {
                Text(problem).font(.caption).foregroundStyle(.secondary)
            }
        }
        if let feedbackError {
            Label(feedbackError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var hints: some View {
        if session.hints.isEmpty {
            Text("No hints in this session.").foregroundStyle(.secondary)
        }
        ForEach(session.hints) { hint in
            VStack(alignment: .leading, spacing: 6) {
                Text(hint.question).font(.scaled(.callout, scale)).foregroundStyle(.secondary)
                MarkdownText(markdown: hint.text)
            }
            Divider()
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if session.transcript.isEmpty {
            Text("No transcript.").foregroundStyle(.secondary)
        }
        ForEach(session.transcript) { line in
            VStack(alignment: .leading, spacing: 2) {
                Text(line.speaker.label)
                    .font(.scaled(.caption, scale, weight: .semibold))
                    .foregroundStyle(line.speaker == .interviewer ? Color.accentColor : .secondary)
                Text(line.text).font(.scaled(.body, scale)).textSelection(.enabled)
            }
        }
    }

    private func addQuestionsToPrep() async {
        guard let client = store.aiClient() else { return }
        isAddingToPrep = true
        prepMessage = nil
        prepError = nil
        do {
            let generator = try AskedQuestionsGenerator(
                client: client, profile: store.profile, stories: store.stories, prepItems: store.prepItems)
            let items = try await generator.generate(from: session)
            store.prepItems += items
            prepMessage = switch items.count {
            case 0: "No new questions: your prep sheet already has them."
            case 1: "Added 1 question to Prep."
            default: "Added \(items.count) questions to Prep."
            }
        } catch {
            prepError = error.localizedDescription
        }
        isAddingToPrep = false
    }

    private func writeFeedback() async {
        guard let client = store.aiClient() else { return }
        isWritingFeedback = true
        draftFeedback = ""
        feedbackError = nil
        do {
            let generator = try FeedbackGenerator(client: client, profile: store.profile, stories: store.stories)
            for try await delta in generator.stream(transcript: PromptContext.transcript(session.transcript)) {
                draftFeedback += delta
            }
            var updated = session
            updated.feedback = draftFeedback
            store.save(updated)
        } catch {
            feedbackError = error.localizedDescription
        }
        isWritingFeedback = false
    }
}

import SwiftUI

/// Practice Mode: choose a format, answer the AI interviewer, read the feedback.
struct PracticeView: View {
    @Environment(AppStore.self) private var store
    @Environment(PracticeSession.self) private var practice
    @ViewState private var interviewType = InterviewType.behavioral
    @ViewState private var questionCount = 5
    @Environment(\.textScale) private var scale

    var body: some View {
        Group {
            switch practice.phase {
            case .idle, .preparing:
                setup
            case .interviewerSpeaking, .waitingForAnswer, .listening:
                interview
            case .writingFeedback, .finished:
                report
            }
        }
        .navigationTitle("Practice")
    }

    // MARK: Setup

    private var setup: some View {
        Form {
            Section {
                Picker("Interview type", selection: $interviewType) {
                    ForEach(InterviewType.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Questions: \(questionCount)", value: $questionCount, in: 1...10)
                LabeledContent("Role") {
                    Text(roleSummary).foregroundStyle(.secondary)
                }
            } footer: {
                Text("The interviewer uses your profile from Setup. You answer by voice, or by typing.")
            }
            if let error = practice.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                if practice.phase == .preparing {
                    ProgressView().controlSize(.small)
                    Text(practice.preparingStatus).foregroundStyle(.secondary)
                    Button("Cancel") { practice.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
                Button("Start practice") {
                    practice.begin(configuration)
                }
                .buttonStyle(.borderedProminent)
                .disabled(practice.phase == .preparing)
            }
        }
        .formStyle(.grouped)
    }

    private var roleSummary: String {
        let parts = [store.profile.targetRole, store.profile.targetCompany].filter { !$0.isEmpty }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " at ")
    }

    private var configuration: PracticeSession.Configuration {
        PracticeSession.Configuration(
            interviewType: interviewType,
            questionCount: questionCount,
            readsAloud: store.settings.readsPracticeQuestionsAloud,
            locale: Locale(identifier: store.settings.localeIdentifier),
            ai: store.aiClient(),
            aiProblem: store.aiProblem,
            profile: store.profile,
            stories: store.stories,
            extraVocabulary: store.settings.extraVocabulary,
            prefersTermAccuracy: store.settings.prefersTermAccuracy)
    }

    // MARK: Interview

    private var interview: some View {
        @Bindable var practice = practice
        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(practice.lines) { line in
                            bubble(line.speaker, line.text)
                        }
                        if practice.phase == .interviewerSpeaking {
                            if practice.interviewerDraft.isEmpty {
                                ProgressView().controlSize(.small)
                            } else {
                                bubble(.interviewer, practice.interviewerDraft)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: practice.lines) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: practice.interviewerDraft) { proxy.scrollTo("end", anchor: .bottom) }
            }

            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Question \(practice.questionsAsked) of \(practice.questionCount)")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let error = practice.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange).lineLimit(2)
                        if practice.canRetry {
                            Button("Retry") { practice.retry() }
                        }
                    }
                }
                TextEditor(text: $practice.answerDraft)
                    .font(.scaled(.body, scale))
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.background.secondary, in: .rect(cornerRadius: 8))
                    .overlay(alignment: .bottomLeading) {
                        if !practice.volatileAnswer.isEmpty {
                            Text(practice.volatileAnswer)
                                .font(.scaled(.body, scale))
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                    }
                    .disabled(practice.phase == .interviewerSpeaking)
                HStack {
                    if practice.phase == .listening {
                        Button {
                            Task { await practice.stopAnswering() }
                        } label: {
                            Label("Stop recording", systemImage: "stop.circle")
                        }
                        .tint(.red)
                    } else {
                        Button {
                            Task { await practice.startAnswering() }
                        } label: {
                            Label("Answer by voice", systemImage: "mic")
                        }
                        .disabled(practice.phase != .waitingForAnswer)
                    }
                    Spacer()
                    Button("End & get feedback") {
                        Task { await finish { await practice.finish() } }
                    }
                    Button(practice.isLastQuestion ? "Send & finish" : "Send answer") {
                        Task { await finish { await practice.submitAnswer() } }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(practice.phase == .interviewerSpeaking
                              || practice.answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
        }
    }

    private func finish(_ action: () async -> Session?) async {
        if let session = await action() { store.save(session) }
    }

    private func bubble(_ speaker: Speaker, _ text: String) -> some View {
        VStack(alignment: speaker == .me ? .trailing : .leading, spacing: 3) {
            Text(speaker.label).font(.scaled(.caption, scale, weight: .semibold)).foregroundStyle(.secondary)
            Text(text)
                .font(.scaled(.body, scale))
                .textSelection(.enabled)
                .padding(10)
                .background(speaker == .me ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.12),
                            in: .rect(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, alignment: speaker == .me ? .trailing : .leading)
    }

    // MARK: Report

    private var report: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if practice.phase == .writingFeedback {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Writing your feedback report…").foregroundStyle(.secondary)
                        }
                    }
                    if let error = practice.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    MarkdownText(markdown: practice.feedback)
                }
                .padding(20)
            }
            if practice.phase == .finished {
                Divider()
                HStack {
                    Text("Saved in Sessions.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("New practice") { practice.cancel() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }
        }
    }
}

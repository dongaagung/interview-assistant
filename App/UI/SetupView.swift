import SwiftUI

/// AI provider, profile, STAR stories, and speech/audio preferences.
struct SetupView: View {
    @Environment(AppStore.self) private var store
    @ViewState private var editingStoryID: StarStory.ID?
    @ViewState private var locales: [Locale] = []
    @ViewState private var extraTermsDraft = ""
    @ViewState private var importsResume = false
    @ViewState private var resumeImportError: String?

    var body: some View {
        @Bindable var store = store
        Form {
            AIProviderSection()

            Section("Profile") {
                TextField("Your name", text: $store.profile.name)
                TextField("Target role", text: $store.profile.targetRole, prompt: Text("e.g. Senior iOS Engineer"))
                TextField("Company", text: $store.profile.targetCompany)
                LabeledEditor(title: "Background", hint: "Resume summary: experience, skills, achievements with numbers.", text: $store.profile.background)
                LabeledEditor(title: "Job description", hint: "Paste the job posting.", text: $store.profile.jobDescription)
                LabeledEditor(
                    title: "Resume / CV",
                    hint: "Hints answer questions about your experience from this. Email and phone numbers are removed on import.",
                    text: $store.profile.resume,
                    minHeight: 160)
                HStack {
                    Button("Import CV…") { importsResume = true }
                    if let resumeImportError {
                        Text(resumeImportError).font(.caption).foregroundStyle(.red)
                    }
                }
                TextField("Hint & feedback language", text: $store.profile.answerLanguage, prompt: Text("Same as the interviewer"))
            }

            Section {
                ForEach($store.stories) { $story in
                    DisclosureGroup(isExpanded: expansion(for: story.id)) {
                        StoryEditor(story: $story)
                    } label: {
                        HStack {
                            Text(story.title.isEmpty ? "Untitled story" : story.title)
                            Spacer()
                            Button(role: .destructive) {
                                store.stories.removeAll { $0.id == story.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete story")
                        }
                    }
                }
                Button {
                    let story = StarStory()
                    store.stories.append(story)
                    editingStoryID = story.id
                } label: {
                    Label("Add STAR story", systemImage: "plus")
                }
            } header: {
                Text("STAR stories")
            } footer: {
                Text("Hints pick the best-fitting story for behavioral questions.")
            }

            Section {
                Picker("Hint style", selection: $store.settings.hintStyle) {
                    ForEach(HintStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Text size") {
                    TextSizeControl()
                }
            } header: {
                Text("Live hints")
            } footer: {
                Text(store.settings.hintStyle == .guide
                     ? "A bold answer line and a few short, decisive points to glance at. Text size also changes with ⌘= and ⌘−."
                     : "A complete answer of about one minute, in your voice. Experience comes only from your profile and STAR stories.")
            }

            Section {
                Picker("Speech language", selection: $store.settings.localeIdentifier) {
                    if locales.isEmpty {
                        Text(store.settings.localeIdentifier).tag(store.settings.localeIdentifier)
                    }
                    ForEach(locales, id: \.self) { locale in
                        Text(PracticeSession.languageName(locale)).tag(locale.identifier(.bcp47))
                    }
                }
                TextField("Extra terms", text: $extraTermsDraft, prompt: Text("e.g. Tokopedia, OVO, Camunda"), axis: .vertical)
                    .lineLimit(1...3)
                    .onChange(of: extraTermsDraft) { store.settings.extraVocabulary = extraTermsDraft.commaSeparatedItems }
                Toggle(isOn: $store.settings.prefersTermAccuracy) {
                    Text("Better recognition of tech terms")
                    Text("Hears Hibernate, jOOQ or HikariCP correctly, but captions finish 0.5–1 s later, which can push hints past 2 s. Indonesian always works this way.")
                }
                Toggle("Show floating overlay during live sessions", isOn: $store.settings.showsOverlay)
                Toggle("Read practice questions aloud", isOn: $store.settings.readsPracticeQuestionsAloud)
            } header: {
                Text("Speech & audio")
            } footer: {
                Text("Speech recognition runs on this Mac. It knows common Java, architecture and cloud terms, plus the technologies in your profile and stories; add others above, separated by commas. Use headphones so the microphone doesn't pick up the interviewer.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Setup")
        .fileImporter(isPresented: $importsResume, allowedContentTypes: ResumeImport.contentTypes) { result in
            do {
                store.profile.resume = try ResumeImport.text(from: result.get())
                resumeImportError = nil
            } catch {
                resumeImportError = error.localizedDescription
            }
        }
        .task {
            locales = await SpeechAnalyzerProvider.supportedLocales()
        }
        .onAppear {
            extraTermsDraft = store.settings.extraVocabulary.joined(separator: ", ")
        }
    }

    private func expansion(for id: StarStory.ID) -> Binding<Bool> {
        Binding(
            get: { editingStoryID == id },
            set: { editingStoryID = $0 ? id : nil })
    }
}

private struct StoryEditor: View {
    @Binding var story: StarStory
    @ViewState private var tagsDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $story.title, prompt: Text("e.g. Cut checkout crashes by 80%"))
            LabeledEditor(title: "Situation", text: $story.situation)
            LabeledEditor(title: "Task", text: $story.task)
            LabeledEditor(title: "Action", text: $story.action)
            LabeledEditor(title: "Result", hint: "Include numbers where you can.", text: $story.result)
            TextField("Tags", text: $tagsDraft, prompt: Text("leadership, conflict, Kafka"))
                .onChange(of: tagsDraft) { story.tags = tagsDraft.commaSeparatedItems }
        }
        .padding(.vertical, 4)
        .onAppear { tagsDraft = story.tags.joined(separator: ", ") }
    }
}

private struct LabeledEditor: View {
    let title: String
    var hint: String?
    @Binding var text: String
    var minHeight: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background.secondary, in: .rect(cornerRadius: 6))
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension String {
    /// "Kafka, , Spring Boot," → ["Kafka", "Spring Boot"]. List fields are
    /// edited as raw text and parsed with this, so a comma isn't swallowed
    /// the moment it's typed.
    var commaSeparatedItems: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

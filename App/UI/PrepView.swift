import SwiftUI

/// The prep sheet: likely questions with prepared answers, generated from
/// the profile and CV, then reviewed and edited before the interview.
struct PrepView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.textScale) private var scale
    @ViewState private var questionCount = 20
    @ViewState private var search = ""
    @ViewState private var isGenerating = false
    @ViewState private var writtenSoFar = 0
    @ViewState private var error: String?
    @ViewState private var confirmsReplace = false
    @ViewState private var isWritingQuestions = false
    @ViewState private var confirmsReplaceQuestions = false
    @ViewState private var expandedID: PrepItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.prepItems.isEmpty && !isGenerating {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Prep sheet")
        .searchable(text: $search, prompt: "Search questions and answers")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Stepper("Questions: \(questionCount)", value: $questionCount, in: 10...30, step: 5)
                .fixedSize()
                .disabled(isGenerating)
            if isGenerating {
                ProgressView().controlSize(.small)
                Text(writtenSoFar == 0 ? "Thinking…" : "Writing… \(writtenSoFar) questions so far")
                    .foregroundStyle(.secondary)
            } else if isWritingQuestions {
                ProgressView().controlSize(.small)
                Text("Writing your questions…").foregroundStyle(.secondary)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                let item = PrepItem()
                store.prepItems.append(item)
                expandedID = item.id
            } label: {
                Label("Add question", systemImage: "plus")
            }
            .disabled(isGenerating)
            Button {
                if hasQuestionsToAsk { confirmsReplaceQuestions = true } else { Task { await writeQuestionsToAsk() } }
            } label: {
                Label("Questions to ask them", systemImage: "questionmark.bubble")
            }
            .help("Write the questions you ask when the interviewer says \u{201C}Do you have any questions for us?\u{201D}")
            .disabled(isBusy || !store.isAIReady)
            .confirmationDialog(
                "Replace your questions for the interviewer, including any edits?",
                isPresented: $confirmsReplaceQuestions
            ) {
                Button("Replace", role: .destructive) { Task { await writeQuestionsToAsk() } }
            }
            Button(replacedCount == 0 ? "Generate" : "Regenerate") {
                if replacedCount == 0 { Task { await generate() } } else { confirmsReplace = true }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || !store.isAIReady)
            .confirmationDialog(
                "Replace your \(replacedCount) generated answers, including any edits?",
                isPresented: $confirmsReplace
            ) {
                Button("Replace", role: .destructive) { Task { await generate() } }
            } message: {
                Text("Questions from your interviews and your questions for the interviewer stay.")
            }
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.clipboard").font(.largeTitle).foregroundStyle(.secondary)
            Text("Prepare before the interview")
                .font(.scaled(.title3, scale, weight: .semibold))
            Text("""
                Generate the questions you're most likely to be asked, with answers built from your profile, \
                CV and STAR stories. Review and edit them. During a live interview, a clearly matching question \
                shows its prepared answer instantly, and every hint builds on these answers.
                """)
                .font(.scaled(.body, scale))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            if let problem = store.aiProblem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        @Bindable var store = store
        return List {
            ForEach(categories, id: \.self) { category in
                Section(category) {
                    ForEach($store.prepItems) { $item in
                        if item.category == category && matchesSearch(item) {
                            PrepRow(item: $item, isExpanded: expansion(for: item.id)) {
                                store.prepItems.removeAll { $0.id == item.id }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
    }

    private var isBusy: Bool { isGenerating || isWritingQuestions }

    /// Items that regenerating would replace.
    private var replacedCount: Int {
        store.prepItems.count - PrepItem.replacingGenerated(in: store.prepItems, with: []).count
    }

    private var hasQuestionsToAsk: Bool {
        store.prepItems.contains { $0.category == PrepItem.yourQuestionsCategory }
    }

    /// Generated categories in their usual order, then any others.
    private var categories: [String] {
        let present = Set(store.prepItems.map(\.category))
        return PrepItem.categories.filter(present.contains) + present.subtracting(PrepItem.categories).sorted()
    }

    private func matchesSearch(_ item: PrepItem) -> Bool {
        search.isEmpty
            || item.question.localizedCaseInsensitiveContains(search)
            || item.answer.localizedCaseInsensitiveContains(search)
    }

    private func expansion(for id: PrepItem.ID) -> Binding<Bool> {
        Binding(get: { expandedID == id }, set: { expandedID = $0 ? id : nil })
    }

    private func generate() async {
        guard let client = store.aiClient() else { return }
        isGenerating = true
        writtenSoFar = 0
        error = nil
        do {
            let generator = try PrepGenerator(
                client: client, profile: store.profile, stories: store.stories,
                questionCount: questionCount, locale: Locale(identifier: store.settings.localeIdentifier))
            let generated = try await generator.generate { writtenSoFar = $0 }
            store.prepItems = PrepItem.replacingGenerated(in: store.prepItems, with: generated)
        } catch {
            self.error = error.localizedDescription
        }
        isGenerating = false
    }

    private func writeQuestionsToAsk() async {
        guard let client = store.aiClient() else { return }
        isWritingQuestions = true
        error = nil
        do {
            let generator = try QuestionsToAskGenerator(
                client: client, profile: store.profile, locale: Locale(identifier: store.settings.localeIdentifier))
            var item = try await generator.generate()
            if let index = store.prepItems.firstIndex(where: { $0.category == PrepItem.yourQuestionsCategory }) {
                item.id = store.prepItems[index].id
                store.prepItems[index] = item
            } else {
                store.prepItems.append(item)
            }
            expandedID = item.id
        } catch {
            self.error = error.localizedDescription
        }
        isWritingQuestions = false
    }
}

private struct PrepRow: View {
    @Binding var item: PrepItem
    @Binding var isExpanded: Bool
    let onDelete: () -> Void
    @Environment(\.textScale) private var scale
    @ViewState private var isEditing = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if isEditing || item.question.isEmpty {
                    TextField("Question", text: $item.question, axis: .vertical)
                        .font(.scaled(.body, scale))
                    Picker("Category", selection: $item.category) {
                        ForEach(PrepItem.categories + [PrepItem.yourQuestionsCategory, "Custom"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .fixedSize()
                    TextEditor(text: $item.answer)
                        .font(.scaled(.body, scale).monospaced())
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(.background.secondary, in: .rect(cornerRadius: 6))
                    Text("Markdown: **bold**, one point per \"- \" line.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    MarkdownText(markdown: item.answer.isEmpty ? "_No answer yet._" : item.answer)
                }
                HStack {
                    Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
                    Spacer()
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 6)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Text(item.question.isEmpty ? "New question" : item.question)
                    .font(.scaled(.body, scale, weight: .semibold))
                if let askedAt = item.askedAt {
                    Text("Asked \(askedAt.formatted(.dateTime.day().month()))")
                        .font(.scaled(.caption, scale))
                        .foregroundStyle(.secondary)
                        .help("A real interview asked this")
                }
            }
        }
    }
}

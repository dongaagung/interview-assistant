import SwiftUI

/// Setup's AI provider section: pick exactly one provider, then its key,
/// server address and models.
struct AIProviderSection: View {
    @Environment(AppStore.self) private var store
    @ViewState private var keyDraft = ""
    @ViewState private var availableModels: [String] = []
    @ViewState private var isLoadingModels = false
    @ViewState private var modelsError: String?

    private var provider: AIProvider { store.settings.aiProvider }

    var body: some View {
        @Bindable var store = store
        Section {
            Picker("Provider", selection: $store.settings.aiProvider) {
                ForEach(AIProvider.allCases) { Text($0.label).tag($0) }
            }
            .onChange(of: store.settings.aiProvider) {
                keyDraft = ""
                availableModels = []
                modelsError = nil
            }

            if provider.acceptsAPIKey {
                let hasKey = store.providersWithKeys.contains(provider)
                HStack {
                    SecureField(
                        "\(provider.shortName) API key", text: $keyDraft,
                        prompt: Text(hasKey ? "Saved. Paste a new key to replace it" : provider.keyPlaceholder))
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .disabled(keyDraft.isEmpty)
                    if hasKey {
                        Button("Remove", role: .destructive) { store.setAPIKey("", for: provider) }
                    }
                }
            }

            if provider == .anthropic {
                LabeledContent("Models") {
                    Text("Haiku 5.5 for hints · Sonnet 5.5 for practice, feedback and prep")
                        .foregroundStyle(.secondary)
                }
            } else {
                TextField(
                    "Server address", text: models(\.baseURL),
                    prompt: Text(provider.defaultBaseURL.isEmpty ? "https://…/v1" : provider.defaultBaseURL))
                ModelField(
                    title: "Fast model",
                    hint: "Question detection and live hints. Pick a fast model that answers without reasoning first.",
                    value: models(\.fastModel), options: availableModels)
                ModelField(
                    title: "Smart model",
                    hint: "Practice interviewer, feedback reports and the prep sheet.",
                    value: models(\.smartModel), options: availableModels)
                HStack {
                    Button("Load models") { Task { await loadModels() } }
                        .disabled(isLoadingModels)
                    if isLoadingModels {
                        ProgressView().controlSize(.small)
                    } else if let modelsError {
                        Text(modelsError).font(.caption).foregroundStyle(.red).lineLimit(2)
                    } else if !availableModels.isEmpty {
                        Text("\(availableModels.count) models. Choose from the menus above.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Label(
                store.aiProblem ?? "Ready: \(provider.shortName)",
                systemImage: store.isAIReady ? "checkmark.seal" : "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(store.isAIReady ? .green : .orange)
        } header: {
            Text("AI provider")
        } footer: {
            Text("""
                Only the selected provider is used. Your profile, CV and the interview conversation are sent to it; \
                keys stay in your Keychain. The prompts are tuned for Claude, so other models may answer differently.
                """)
        }
    }

    /// The active provider's address or model, defaulting the address.
    private func models(_ field: WritableKeyPath<ProviderModels, String>) -> Binding<String> {
        Binding(
            get: { store.settings.models(for: provider)[keyPath: field] },
            set: { value in
                var models = store.settings.models(for: provider)
                models[keyPath: field] = value
                store.settings.providerModels[provider] = models
            })
    }

    private func saveKey() {
        guard !keyDraft.isEmpty else { return }
        store.setAPIKey(keyDraft, for: provider)
        keyDraft = ""
    }

    private func loadModels() async {
        let address = store.settings.models(for: provider).baseURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: address), url.host() != nil else {
            modelsError = "Enter the server address first."
            return
        }
        isLoadingModels = true
        modelsError = nil
        do {
            availableModels = try await OpenAICompatibleClient.listModels(
                baseURL: url, apiKey: provider.acceptsAPIKey ? store.apiKey(for: provider) : nil)
            if availableModels.isEmpty { modelsError = "The server listed no models." }
        } catch {
            availableModels = []
            modelsError = error.localizedDescription
        }
        isLoadingModels = false
    }
}

/// A model name: typed, or chosen from the models the server listed.
private struct ModelField: View {
    let title: String
    let hint: String
    @Binding var value: String
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(title, text: $value, prompt: Text("Model name"))
                if !options.isEmpty {
                    Menu("Choose") {
                        ForEach(options, id: \.self) { option in
                            Button(option) { value = option }
                        }
                    }
                    .fixedSize()
                }
            }
            Text(hint).font(.caption).foregroundStyle(.secondary)
        }
    }
}

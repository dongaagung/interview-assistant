import Foundation
import Observation

/// App-wide state persisted as JSON in Application Support. The API key is
/// the exception: it only ever goes to the Keychain.
@MainActor
@Observable
final class AppStore {
    var profile = Profile() {
        didSet { persist(profile, to: Self.profileFile) }
    }
    var stories: [StarStory] = [] {
        didSet { persist(stories, to: Self.storiesFile) }
    }
    var settings = AppSettings() {
        didSet { persist(settings, to: Self.settingsFile) }
    }
    var prepItems: [PrepItem] = [] {
        didSet { persist(prepItems, to: Self.prepFile) }
    }
    /// Newest first.
    private(set) var sessions: [Session] = []
    /// Providers with a key in the Keychain.
    private(set) var providersWithKeys: Set<AIProvider> = []
    /// Last persistence error, shown in the UI.
    var lastError: String?

    private let files: JSONFileStore?
    /// Prepended to Keychain account names; tests use their own.
    private let keychainPrefix: String

    static let profileFile = "profile.json"
    static let storiesFile = "stories.json"
    static let settingsFile = "settings.json"
    static let prepFile = "prep.json"
    static let sessionsDirectory = "sessions"

    init(files: JSONFileStore? = try? .applicationSupport(), keychainPrefix: String = "") {
        self.files = files
        self.keychainPrefix = keychainPrefix
        guard let files else {
            lastError = "Can't open Application Support; changes won't be saved."
            return
        }
        do {
            profile = try files.load(Profile.self, from: Self.profileFile) ?? Profile()
            stories = try files.load([StarStory].self, from: Self.storiesFile) ?? []
            settings = try files.load(AppSettings.self, from: Self.settingsFile) ?? AppSettings()
            prepItems = try files.load([PrepItem].self, from: Self.prepFile) ?? []
            sessions = try files.list(Self.sessionsDirectory)
                .compactMap { try files.load(Session.self, from: "\(Self.sessionsDirectory)/\($0)") }
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            lastError = "Couldn't load saved data: \(error.localizedDescription)"
        }
        providersWithKeys = Set(AIProvider.allCases.filter { $0.acceptsAPIKey && apiKey(for: $0) != nil })
    }

    // MARK: Sessions

    func save(_ session: Session) {
        persist(session, to: Self.sessionPath(session.id))
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
            sessions.sort { $0.startedAt > $1.startedAt }
        }
    }

    func delete(_ session: Session) {
        do {
            try files?.remove(Self.sessionPath(session.id))
            sessions.removeAll { $0.id == session.id }
        } catch {
            lastError = "Couldn't delete session: \(error.localizedDescription)"
        }
    }

    private static func sessionPath(_ id: UUID) -> String {
        "\(sessionsDirectory)/\(id.uuidString).json"
    }

    // MARK: AI provider

    func apiKey(for provider: AIProvider) -> String? {
        guard let key = Keychain.read(account: keychainPrefix + provider.keychainAccount), !key.isEmpty else {
            return nil
        }
        return key
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = keychainPrefix + provider.keychainAccount
        do {
            if trimmed.isEmpty {
                try Keychain.delete(account: account)
                providersWithKeys.remove(provider)
            } else {
                try Keychain.save(trimmed, account: account)
                providersWithKeys.insert(provider)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// What's missing before the active provider can be used, or nil.
    var aiProblem: String? {
        let provider = settings.aiProvider
        if provider.requiresAPIKey && !providersWithKeys.contains(provider) {
            return "Add your \(provider.shortName) API key in Setup."
        }
        guard provider != .anthropic else { return nil }
        let models = settings.models(for: provider)
        if URL(string: models.baseURL.trimmingCharacters(in: .whitespaces))?.host() == nil {
            return "Enter the server address for \(provider.shortName) in Setup."
        }
        if models.fastModel.trimmingCharacters(in: .whitespaces).isEmpty
            || models.smartModel.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Choose the \(provider.shortName) models in Setup."
        }
        return nil
    }

    var isAIReady: Bool { aiProblem == nil }

    /// A client for the active provider, or nil while `aiProblem` says why not.
    func aiClient() -> (any LLMClient)? {
        guard isAIReady else { return nil }
        let provider = settings.aiProvider
        let key = provider.acceptsAPIKey ? apiKey(for: provider) : nil
        if provider == .anthropic {
            return key.map { ClaudeClient(apiKey: $0) }
        }
        let models = settings.models(for: provider)
        guard let baseURL = URL(string: models.baseURL.trimmingCharacters(in: .whitespaces)) else { return nil }
        return OpenAICompatibleClient(
            providerName: provider.shortName,
            baseURL: baseURL,
            apiKey: key,
            fastModel: models.fastModel.trimmingCharacters(in: .whitespaces),
            smartModel: models.smartModel.trimmingCharacters(in: .whitespaces),
            usesMaxCompletionTokens: provider.usesMaxCompletionTokens,
            disablesThinkingForSpeed: provider.disablesThinkingForSpeed,
            supportsJSONSchema: provider.supportsJSONSchema)
    }

    // MARK: Persistence

    private func persist<T: Encodable>(_ value: T, to path: String) {
        do {
            try files?.save(value, to: path)
        } catch {
            lastError = "Couldn't save \(path): \(error.localizedDescription)"
        }
    }
}

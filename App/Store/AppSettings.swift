import Foundation

/// Where the interviewer's voice comes from.
enum MeetingAudioSource: Codable, Hashable, Sendable {
    /// Everything the Mac plays. Works with any meeting app or browser tab.
    case systemWide
    /// Only one app (and its helper processes), identified by its bundle ID.
    case app(bundleID: String, name: String)

    var label: String {
        switch self {
        case .systemWide: "All system audio"
        case .app(_, let name): name
        }
    }
}

/// How live hints are written.
enum HintStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A bold main point and a few bullets to glance at.
    case guide
    /// A complete first-person answer to say in your own voice.
    case fullAnswer

    var id: Self { self }

    var label: String {
        switch self {
        case .guide: "Short guide"
        case .fullAnswer: "Full answer"
        }
    }

    /// The template in prompts/ that writes this style.
    var templateName: String {
        switch self {
        case .guide: "hint"
        case .fullAnswer: "hint_full"
        }
    }

    var maxTokens: Int {
        switch self {
        case .guide: 600
        case .fullAnswer: 1_200
        }
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var meetingAudio: MeetingAudioSource = .systemWide
    /// Speech recognition locale for both speakers, as a BCP 47 identifier.
    var localeIdentifier = "en-US"
    var showsOverlay = true
    var readsPracticeQuestionsAloud = true
    var hintStyle = HintStyle.guide
    /// Terms to recognize on top of the built-in IT list and the profile.
    var extraVocabulary: [String] = []
    /// Recognize with DictationTranscriber, which uses the vocabulary, even
    /// where SpeechTranscriber supports the language. Captions finalize
    /// about 0.5 to 1 s later.
    var prefersTermAccuracy = false
    /// Multiplier for caption, hint and practice text. See `TextScale`.
    var textScale = TextScale.standard
    /// The one provider all AI features use.
    var aiProvider = AIProvider.anthropic
    /// Server address and models per OpenAI-compatible provider, kept when
    /// switching so switching back needs no re-entry.
    var providerModels: [AIProvider: ProviderModels] = [:]

    init() {}

    /// The active provider's address and models, with its default address
    /// filled in before the user changes it.
    func models(for provider: AIProvider) -> ProviderModels {
        providerModels[provider] ?? ProviderModels(baseURL: provider.defaultBaseURL)
    }

    /// Fields missing from an older settings.json keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        meetingAudio = try container.decodeIfPresent(MeetingAudioSource.self, forKey: .meetingAudio) ?? defaults.meetingAudio
        localeIdentifier = try container.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? defaults.localeIdentifier
        showsOverlay = try container.decodeIfPresent(Bool.self, forKey: .showsOverlay) ?? defaults.showsOverlay
        readsPracticeQuestionsAloud = try container.decodeIfPresent(Bool.self, forKey: .readsPracticeQuestionsAloud)
            ?? defaults.readsPracticeQuestionsAloud
        hintStyle = try container.decodeIfPresent(HintStyle.self, forKey: .hintStyle) ?? defaults.hintStyle
        extraVocabulary = try container.decodeIfPresent([String].self, forKey: .extraVocabulary)
            ?? defaults.extraVocabulary
        prefersTermAccuracy = try container.decodeIfPresent(Bool.self, forKey: .prefersTermAccuracy)
            ?? defaults.prefersTermAccuracy
        textScale = try container.decodeIfPresent(Double.self, forKey: .textScale) ?? defaults.textScale
        aiProvider = try container.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? defaults.aiProvider
        providerModels = try container.decodeIfPresent([AIProvider: ProviderModels].self, forKey: .providerModels)
            ?? defaults.providerModels
    }
}

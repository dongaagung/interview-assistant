import Foundation

/// Who the candidate is and what they're interviewing for. Feeds the hint,
/// practice and feedback prompts.
struct Profile: Codable, Equatable, Sendable {
    var name = ""
    var targetRole = ""
    var targetCompany = ""
    /// Resume summary: experience, skills, notable achievements.
    var background = ""
    var jobDescription = ""
    /// Language for hints and feedback. Empty means "match the interviewer".
    var answerLanguage = ""
    /// The full CV as text. Hints answer questions about the candidate's
    /// history from it, and from nothing else.
    var resume = ""
}

extension Profile {
    /// Fields missing from an older profile.json keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? name
        targetRole = try container.decodeIfPresent(String.self, forKey: .targetRole) ?? targetRole
        targetCompany = try container.decodeIfPresent(String.self, forKey: .targetCompany) ?? targetCompany
        background = try container.decodeIfPresent(String.self, forKey: .background) ?? background
        jobDescription = try container.decodeIfPresent(String.self, forKey: .jobDescription) ?? jobDescription
        answerLanguage = try container.decodeIfPresent(String.self, forKey: .answerLanguage) ?? answerLanguage
        resume = try container.decodeIfPresent(String.self, forKey: .resume) ?? resume
    }
}

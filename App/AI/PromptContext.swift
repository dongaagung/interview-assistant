import Foundation

/// Renders app data into the text that fills prompt-template variables.
/// Output must be deterministic: it sits in cached system prompts.
enum PromptContext {
    static func profile(_ profile: Profile) -> String {
        var parts: [String] = []
        if !profile.name.isEmpty { parts.append("Name: \(profile.name)") }
        if !profile.targetRole.isEmpty { parts.append("Target role: \(profile.targetRole)") }
        if !profile.targetCompany.isEmpty { parts.append("Company: \(profile.targetCompany)") }
        if !profile.background.isEmpty { parts.append("Background:\n\(profile.background)") }
        if !profile.jobDescription.isEmpty { parts.append("Job description:\n\(profile.jobDescription)") }
        if !profile.resume.isEmpty { parts.append("Resume (CV):\n\(profile.resume)") }
        return parts.isEmpty ? "(No profile provided.)" : parts.joined(separator: "\n\n")
    }

    static func stories(_ stories: [StarStory]) -> String {
        guard !stories.isEmpty else { return "(No STAR stories provided.)" }
        return stories.map { story in
            var lines = ["### \(story.title.isEmpty ? "Untitled story" : story.title)"]
            if !story.situation.isEmpty { lines.append("Situation: \(story.situation)") }
            if !story.task.isEmpty { lines.append("Task: \(story.task)") }
            if !story.action.isEmpty { lines.append("Action: \(story.action)") }
            if !story.result.isEmpty { lines.append("Result: \(story.result)") }
            if !story.tags.isEmpty { lines.append("Tags: \(story.tags.joined(separator: ", "))") }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func prepSheet(_ items: [PrepItem]) -> String {
        guard !items.isEmpty else { return "(No prepared answers.)" }
        return items.map { "Q: \($0.question)\nA:\n\($0.answer)" }.joined(separator: "\n\n")
    }

    static func answerLanguage(_ profile: Profile) -> String {
        let language = profile.answerLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return language.isEmpty ? "the same language the interviewer uses" : language
    }

    static func transcript(_ lines: [TranscriptLine]) -> String {
        lines.map { "\($0.speaker.label): \($0.text)" }.joined(separator: "\n")
    }

    /// The tail of a transcript, cut at a line boundary.
    static func recentTranscript(_ lines: [TranscriptLine], maxCharacters: Int) -> String {
        var kept: [String] = []
        var length = 0
        for line in lines.reversed() {
            let text = "\(line.speaker.label): \(line.text)"
            if length + text.count > maxCharacters, !kept.isEmpty { break }
            kept.append(text)
            length += text.count + 1
        }
        return kept.reversed().joined(separator: "\n")
    }
}

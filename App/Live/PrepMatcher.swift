import Foundation
import NaturalLanguage

/// Finds the prep-sheet question a spoken question clearly is, so its
/// prepared answer can show instantly, with no API call.
///
/// Deliberately strict. macOS sentence embeddings were tried and paired
/// "What is Kafka…" with "What is your notice period?"; a wrong answer shown
/// instantly is worse than a live hint a second later. So this only matches
/// when nearly all of the prepared question's content words are spoken, and
/// most of what was spoken is covered: "tell me a bit about yourself" or
/// "what's your notice period?". Everything else gets a live hint, which
/// also sees the prep sheet in its prompt.
struct PrepMatcher: Sendable {
    private let entries: [(item: PrepItem, terms: Set<String>)]

    init(items: [PrepItem]) {
        entries = items.map { ($0, Set(Self.terms($0.question))) }.filter { $0.terms.count >= 2 }
    }

    func match(_ spoken: String) -> PrepItem? {
        let spokenTerms = Set(Self.terms(spoken))
        guard spokenTerms.count >= 2 else { return nil }
        var best: (item: PrepItem, score: Double)?
        for entry in entries {
            let shared = entry.terms.intersection(spokenTerms).count
            guard shared >= 2 else { continue }
            let preparedCoverage = Double(shared) / Double(entry.terms.count)
            let spokenCoverage = Double(shared) / Double(spokenTerms.count)
            guard preparedCoverage >= 0.8, spokenCoverage >= 0.6 else { continue }
            let score = preparedCoverage + spokenCoverage
            if score > best?.score ?? 0 { best = (entry.item, score) }
        }
        return best?.item
    }

    /// Lowercased lemmas of the content words ("telling" → "tell").
    static func terms(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var terms: [String] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
            options: [.omitWhitespace, .omitPunctuation, .omitOther]
        ) { tag, range in
            let surface = text[range].lowercased()
            var word = tag?.rawValue.lowercased() ?? surface
            // "yourself" lemmatizes to "you"; keep the word, not the stop-worded lemma.
            if stopWords.contains(word), !stopWords.contains(surface) { word = surface }
            // Contraction tails ("'s", "'re") aren't words.
            let isContractionTail = word.first == "'" || word.first == "’"
            if word.count >= 2, !isContractionTail, !stopWords.contains(word), word.contains(where: \.isLetter) {
                terms.append(word)
            }
            return true
        }
        return terms
    }

    /// Function words, question words and filler that say nothing about
    /// which question it is, in English and Indonesian.
    private static let stopWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "to", "of", "in", "on", "at", "for", "with", "by", "from",
        "about", "as", "into", "is", "are", "was", "were", "be", "been", "am", "do", "does", "did", "have",
        "has", "had", "can", "could", "would", "will", "should", "may", "might", "must", "shall",
        "i", "me", "my", "we", "us", "our", "you", "your", "he", "she", "it", "its", "they", "them", "their",
        "this", "that", "these", "those", "there", "here", "what", "which", "who", "whom", "when", "where",
        "how", "why", "if", "then", "than", "also", "just", "please", "maybe", "bit", "little", "briefly",
        "quickly", "start", "okay", "ok", "well", "now", "really", "kind", "sort", "like", "let", "go",
        "yang", "dan", "di", "ke", "dari", "untuk", "dengan", "ini", "itu", "apa", "apakah", "bagaimana",
        "kenapa", "mengapa", "kapan", "siapa", "anda", "kamu", "saya", "kami", "kita", "bisa", "tolong",
        "coba", "sedikit", "boleh", "ya", "oke", "jadi", "nah", "tentang", "adalah", "ada", "akan",
    ]
}

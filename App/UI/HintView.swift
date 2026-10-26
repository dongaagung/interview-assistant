import SwiftUI

/// The newest answer hint, large, with earlier ones below it.
struct HintView: View {
    let hints: [LiveHint]
    var compact = false
    @Environment(\.textScale) private var scale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let latest = hints.last {
                    HintCard(hint: latest, compact: compact)
                    let earlier = hints.dropLast().reversed()
                    if !earlier.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(earlier)) { hint in
                                    HintCard(hint: hint, compact: true)
                                    Divider()
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            Text("Earlier questions (\(earlier.count))").font(.scaled(.callout, scale))
                        }
                    }
                } else {
                    Text("Answer hints appear here when the interviewer asks a question.")
                        .font(.scaled(.body, scale))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(compact ? 12 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct HintCard: View {
    let hint: LiveHint
    let compact: Bool
    @Environment(\.textScale) private var scale

    /// "First words 1.8 s after the question (listening 0.6 + Claude 1.2)",
    /// or nil before the first words. Asked by hand, it's time since asking.
    private var timing: String? {
        guard let latency = hint.latency else { return nil }
        let total = Self.seconds(latency)
        if hint.isPrepared { return "shown \(total) s after the question" }
        guard hint.listeningDelay >= 0.05, let claude = hint.claudeDelay else {
            return "First words \(total) s after you asked"
        }
        return "First words \(total) s after the question (listening \(Self.seconds(hint.listeningDelay)) + Claude \(Self.seconds(claude)))"
    }

    private static func seconds(_ value: TimeInterval) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hint.question)
                .font(.scaled(.callout, scale))
                .foregroundStyle(.secondary)
                .lineLimit(compact ? 2 : 4)
            if let translation = hint.translation {
                Label(translation, systemImage: "character.bubble")
                    .font(.scaled(.callout, scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 3 : 5)
            }
            if hint.text.isEmpty && hint.isStreaming {
                ProgressView().controlSize(.small)
            } else {
                MarkdownText(markdown: hint.text, style: compact ? .body : .title3)
            }
            if let error = hint.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.scaled(.caption, scale))
                    .foregroundStyle(.red)
            }
            if hint.isPrepared {
                Label(
                    ["From your prep sheet", timing, "\(GlobalHotKey.label) for a live answer"]
                        .compactMap { $0 }.joined(separator: " · "),
                    systemImage: "list.bullet.clipboard")
                    .font(.scaled(.caption2, scale))
                    .foregroundStyle(.secondary)
            } else if let timing, let latency = hint.latency {
                Text(timing)
                    .font(.scaled(.caption2, scale))
                    .foregroundStyle(latency < 2 ? Color.secondary : Color.orange)
                    .help("Measured from when the interviewer stopped talking: listening for the end of the question, then waiting for Claude's first words.")
            }
        }
    }
}

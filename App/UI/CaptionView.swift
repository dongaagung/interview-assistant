import SwiftUI

/// Live captions, consecutive lines by the same speaker merged into one block,
/// with each speaker's in-progress words in grey at the end.
struct CaptionView: View {
    let transcript: Transcript
    var compact = false
    @Environment(\.textScale) private var scale

    private struct Block: Identifiable {
        let id: UUID
        let speaker: Speaker
        var text: String
    }

    private var blocks: [Block] {
        var blocks: [Block] = []
        for line in transcript.lines {
            if let last = blocks.last, last.speaker == line.speaker {
                blocks[blocks.count - 1].text += " " + line.text
            } else {
                blocks.append(Block(id: line.id, speaker: line.speaker, text: line.text))
            }
        }
        return blocks
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: compact ? 6 : 10) {
                    if transcript.lines.isEmpty && transcript.volatileText.isEmpty {
                        Text("Captions appear here once someone speaks.")
                            .font(.scaled(.body, scale))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(blocks) { block in
                        row(block.speaker, Text(block.text))
                    }
                    ForEach([Speaker.interviewer, .me], id: \.self) { speaker in
                        if let text = transcript.volatileText[speaker] {
                            row(speaker, Text(text).foregroundStyle(.secondary))
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(compact ? 10 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: transcript) {
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    private func row(_ speaker: Speaker, _ text: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(speaker.label)
                .font(.scaled(.caption, scale, weight: .semibold))
                .foregroundStyle(speaker == .interviewer ? Color.accentColor : .secondary)
            text
                .font(.scaled(compact ? .callout : .body, scale))
                .textSelection(.enabled)
        }
    }
}

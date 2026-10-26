import SwiftUI

/// "Answering 1:12 · 3 fillers", orange past two minutes. Nothing until the
/// user has said a few words.
struct AnswerMeterView: View {
    let meter: AnswerMeter
    @Environment(\.textScale) private var scale

    var body: some View {
        if meter.hasAnswer {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let duration = meter.duration(at: context.date)
                Label(text(duration), systemImage: meter.isRunning ? "mic.fill" : "mic")
                    .font(.scaled(.caption, scale).monospacedDigit())
                    .foregroundStyle(duration > AnswerMeter.longAnswer ? Color.orange : .secondary)
                    .help("""
                        Timed from your microphone's captions. Answers over two minutes turn orange. \
                        Fillers are "um", "uh", "eh", "anu", "you know" and the like, as far as speech \
                        recognition writes them down.
                        """)
            }
        }
    }

    private func text(_ duration: TimeInterval) -> String {
        let time = Duration.seconds(duration.rounded(.down)).formatted(.time(pattern: .minuteSecond))
        let fillers = meter.fillerCount == 1 ? "1 filler" : "\(meter.fillerCount) fillers"
        return "\(meter.isRunning ? "Answering" : "Last answer") \(time) · \(fillers)"
    }
}

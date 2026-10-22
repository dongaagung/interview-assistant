import Testing
@testable import InterviewAssistant

struct MarkdownTests {
    @Test func parsesHintAndReportShapes() {
        let markdown = """
            **Lead with the migration story.**
            - Cut crashes by **80%**
              - in two sprints
            1. Situation: legacy checkout

            # Overall
            Solid answers.
            Good pacing.
            """
        #expect(MarkdownBlock.parse(markdown) == [
            .paragraph("**Lead with the migration story.**"),
            .bullet(marker: "•", text: "Cut crashes by **80%**", depth: 0),
            .bullet(marker: "•", text: "in two sprints", depth: 1),
            .bullet(marker: "1.", text: "Situation: legacy checkout", depth: 0),
            .heading(level: 1, text: "Overall"),
            .paragraph("Solid answers.\nGood pacing."),
        ])
    }
}

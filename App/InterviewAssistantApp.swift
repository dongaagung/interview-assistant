import SwiftUI

@main
struct InterviewAssistantApp: App {
    @ViewState private var store = AppStore()
    @ViewState private var live = LiveSession()
    @ViewState private var practice = PracticeSession()
    @ViewState private var overlay = OverlayController()

    var body: some Scene {
        WindowGroup("Interview Assistant") {
            ContentView()
                .environment(store)
                .environment(live)
                .environment(practice)
                .environment(overlay)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Bigger Text") {
                    store.settings.textScale = TextScale.bigger(than: store.settings.textScale)
                }
                .keyboardShortcut("=", modifiers: .command)
                Button("Smaller Text") {
                    store.settings.textScale = TextScale.smaller(than: store.settings.textScale)
                }
                .keyboardShortcut("-", modifiers: .command)
                Button("Default Text Size") {
                    store.settings.textScale = TextScale.standard
                }
                .keyboardShortcut("0", modifiers: .command)
                Divider()
            }
        }
    }
}

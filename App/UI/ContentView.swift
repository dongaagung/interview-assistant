import SwiftUI

struct ContentView: View {
    enum Screen: String, CaseIterable, Identifiable {
        case live, prep, practice, sessions, setup

        var id: Self { self }

        var label: String {
            switch self {
            case .live: "Live"
            case .prep: "Prep"
            case .practice: "Practice"
            case .sessions: "Sessions"
            case .setup: "Setup"
            }
        }

        var systemImage: String {
            switch self {
            case .live: "waveform"
            case .prep: "list.bullet.clipboard"
            case .practice: "person.2.wave.2"
            case .sessions: "clock.arrow.circlepath"
            case .setup: "person.text.rectangle"
            }
        }
    }

    @Environment(AppStore.self) private var store
    @Environment(LiveSession.self) private var live
    @Environment(OverlayController.self) private var overlay
    @ViewState private var screen: Screen? = .live

    var body: some View {
        NavigationSplitView {
            List(Screen.allCases, selection: $screen) { screen in
                Label(screen.label, systemImage: screen.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch screen ?? .live {
            case .live: LiveView()
            case .prep: PrepView()
            case .practice: PracticeView()
            case .sessions: SessionsView()
            case .setup: SetupView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = store.lastError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                    Spacer()
                    Button("Dismiss") { store.lastError = nil }
                }
                .padding(10)
                .background(.orange.opacity(0.15))
            }
        }
        .environment(\.textScale, store.settings.textScale)
        .onChange(of: live.phase) { updateOverlay() }
        .onChange(of: store.settings.showsOverlay) { updateOverlay() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            // Quitting mid-interview keeps everything up to now.
            if let session = live.snapshot(ended: true) { store.save(session) }
        }
        .onAppear {
            if !store.isAIReady || store.profile == Profile() { screen = .setup }
        }
    }

    private func updateOverlay() {
        if live.phase == .running && store.settings.showsOverlay {
            overlay.show(live, store: store)
        } else if live.phase == .idle || !store.settings.showsOverlay {
            overlay.hide()
        }
    }
}

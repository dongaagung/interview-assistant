import AppKit
import Observation
import SwiftUI

/// Floating panel with the latest hint and captions. Stays above other
/// windows, on every Space, without taking focus from the meeting app.
final class OverlayPanel: NSPanel {
    init<Content: View>(content: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false)
        title = "Interview Assistant"
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: content)
        if !setFrameUsingName(Self.frameName) {
            placeInTopRightCorner()
        }
        setFrameAutosaveName(Self.frameName)
    }

    private static let frameName = "InterviewAssistantOverlay"

    private func placeInTopRightCorner() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: screen.maxX - frame.width - 20, y: screen.maxY - frame.height - 20))
    }
}

@MainActor
@Observable
final class OverlayController {
    private var panel: OverlayPanel?

    func show(_ live: LiveSession, store: AppStore) {
        if panel == nil {
            panel = OverlayPanel(content: OverlayView().environment(live).environment(store))
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct OverlayView: View {
    @Environment(LiveSession.self) private var live
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    live.hintNow()
                } label: {
                    Label("Hint now \(GlobalHotKey.label)", systemImage: "sparkles")
                }
                .buttonStyle(.borderless)
                .disabled(!live.canHint)
                Spacer()
                // The panel never takes focus from the meeting app, so ⌘= won't
                // reach it; these buttons resize the text instead.
                TextSizeControl()
            }
            .padding(.horizontal, 10)
            .padding(.top, 26)
            VSplitView {
                HintView(hints: live.visibleHints, compact: true)
                    .frame(minHeight: 160, maxHeight: .infinity)
                CaptionView(transcript: live.transcript, compact: true)
                    .frame(minHeight: 90, idealHeight: 150)
            }
        }
        .environment(\.textScale, store.settings.textScale)
        .background(.regularMaterial)
    }
}

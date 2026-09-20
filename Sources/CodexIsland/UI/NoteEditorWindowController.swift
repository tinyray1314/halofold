import AppKit
import SwiftUI

enum AnchoredNoteGeometry {
    static func frame(screen: NSRect, visible: NSRect) -> NSRect {
        let width = min(900, max(1, visible.width - 32))
        let top = screen.maxY - 32
        let height = min(650, max(1, top - visible.minY - 16))
        return NSRect(x: screen.midX - width / 2, y: top - height, width: width, height: height)
    }
}

private final class AnchoredNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NoteEditorWindowController: NSWindowController, NSWindowDelegate {
    private let model: ApplicationModel

    init(model: ApplicationModel) {
        self.model = model
        let window = AnchoredNotePanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "便签工作台"
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.hidesOnDeactivate = false
        window.level = IslandWindowLevelPolicy.normalExpanded
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: NoteEditorWindowView(model: model))
        positionOnIsland()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        showAnchored()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .focusExpandedNoteBody, object: nil)
    }

    func positionOnIsland() {
        guard let screen = NSScreen.main else { return }
        window?.setFrame(AnchoredNoteGeometry.frame(screen: screen.frame, visible: screen.visibleFrame), display: true)
    }

    func showAnchored() {
        positionOnIsland()
        window?.orderFrontRegardless()
    }

    func dismiss() {
        window?.makeFirstResponder(nil)
        model.notes.flush()
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        model.returnToQuickPanel()
        return false
    }
}

private struct NoteEditorWindowView: View {
    @ObservedObject var model: ApplicationModel

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(red: 0.065, green: 0.082, blue: 0.09))
                .frame(width: 42, height: 7)
            content
                .background(Color(red: 0.065, green: 0.082, blue: 0.09), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.13), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .foregroundStyle(.white.opacity(0.9))
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text("便签").font(.system(size: 13, weight: .medium))
                Spacer()
                Button(action: model.returnToQuickPanel) {
                    Label("收回轻面板", systemImage: "arrow.down.right.and.arrow.up.left")
                        .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
                }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.islandMint)
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider().overlay(Color.white.opacity(0.06))
            NotesWorkspaceView(model: model, spacious: true)
            if let notice = model.undoNotice {
                HStack {
                    Text(notice.message)
                    Spacer()
                    Button("撤销", action: model.undoLastDeletion).buttonStyle(.plain).foregroundStyle(Color.islandMint)
                }.font(.system(size: 12)).padding(12).background(Color.white.opacity(0.06))
            }
        }
        .foregroundStyle(.white.opacity(0.9))
        .background(Color(red: 0.065, green: 0.082, blue: 0.09))
        .environment(\.colorScheme, .dark)
    }
}

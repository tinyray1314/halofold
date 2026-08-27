import AppKit
import Combine
import SwiftUI

enum CodexForegroundPolicy {
    static let codexBundleIdentifier = "com.openai.codex"

    static func shouldHide(for bundleIdentifier: String?) -> Bool {
        bundleIdentifier == codexBundleIdentifier
    }
}

enum TopBarGeometry {
    static func notchEdges(
        frameMidX: CGFloat,
        auxiliaryLeftMaxX: CGFloat?,
        auxiliaryRightMinX: CGFloat?
    ) -> (left: CGFloat, right: CGFloat) {
        (
            auxiliaryLeftMaxX ?? (frameMidX - 92.5),
            auxiliaryRightMinX ?? (frameMidX + 92.5)
        )
    }
}

enum IslandWindowLevelPolicy {
    static let normalExpanded = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
    static let whilePresentingSystemPermission = NSWindow.Level.floating
}

enum ExpandedIslandLayout {
    static let panelWidth: CGFloat = 510
    static let workspaceHeight: CGFloat = 443
    static let windowHeight: CGFloat = 465
}

private final class NotchBarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class ExpandedIslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

private final class FullBleedHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
}

@MainActor
final class IslandWindowController: NSWindowController {
    private let model: ApplicationModel
    private let backdropPanel: NotchBarPanel
    private let leftWingPanel: NotchBarPanel
    private let rightWingPanel: NotchBarPanel
    private let expandedPanel: ExpandedIslandPanel
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObserver: NSObjectProtocol?

    private let expandedPanelWidth: CGFloat = ExpandedIslandLayout.panelWidth
    private let notchBarHeight: CGFloat = 32
    private let dashboardHeight: CGFloat = ExpandedIslandLayout.windowHeight
    private let settingsHeight: CGFloat = 505
    private var userHidden = false
    private var codexIsFrontmost = false

    init(model: ApplicationModel) {
        self.model = model

        backdropPanel = Self.makeBackdropPanel(height: notchBarHeight)
        leftWingPanel = Self.makeNotchBarPanel(width: 1, height: notchBarHeight)
        rightWingPanel = Self.makeNotchBarPanel(width: 1, height: notchBarHeight)
        expandedPanel = Self.makeExpandedPanel(width: expandedPanelWidth)
        if ProcessInfo.processInfo.arguments.contains("--notes-demo") {
            leftWingPanel.ignoresMouseEvents = true
            rightWingPanel.ignoresMouseEvents = true
        }

        backdropPanel.contentView = FullBleedHostingView(
            rootView: Capsule().fill(Color.black.opacity(0.995))
        )
        leftWingPanel.contentView = FullBleedHostingView(
            rootView: IslandView(
                model: model,
                presentation: .leftWing
            )
        )
        rightWingPanel.contentView = FullBleedHostingView(
            rootView: IslandView(
                model: model,
                presentation: .rightWing
            )
        )
        expandedPanel.contentView = FullBleedHostingView(
            rootView: IslandView(
                model: model,
                presentation: .expandedContent
            )
        )

        super.init(window: leftWingPanel)
        observeState()
        observeForegroundApplication()
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func toggleUserVisibility() {
        userHidden.toggle()
        updateVisibility()
    }

    func showSettings() {
        userHidden = false
        model.showSettings()
        updateVisibility()
    }

    func showNotesWorkspace() {
        userHidden = false
        codexIsFrontmost = false
        model.showNotesWorkspace()
        updateVisibility()
    }

    func presentNewNote() {
        userHidden = false
        codexIsFrontmost = false
        model.showNotesWorkspace(createNew: true)
        guard let screen = Self.notchScreen else { return }
        showWingPanels(on: screen)
        showExpandedPanel(on: screen, animated: true)
        expandedPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .focusNewNoteTitle, object: nil)
        }
    }

    func updateVisibility() {
        codexIsFrontmost = currentAppIsCodex

        guard !userHidden,
              !codexIsFrontmost,
              model.isShowingSettings || model.settings.hasEnabledModules,
              let screen = Self.notchScreen
        else {
            hideAllPanels()
            return
        }

        showWingPanels(on: screen)

        if model.isExpanded {
            showExpandedPanel(on: screen, animated: false)
        } else {
            expandedPanel.orderOut(nil)
        }
    }

    private var currentAppIsCodex: Bool {
        guard !ProcessInfo.processInfo.arguments.contains("--ignore-codex-foreground") else {
            return false
        }
        return CodexForegroundPolicy.shouldHide(
            for: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
    }

    private func observeState() {
        model.$isExpanded
            .removeDuplicates()
            .sink { [weak self] expanded in
                self?.expandedStateChanged(expanded)
            }
            .store(in: &cancellables)

        model.$isShowingSettings
            .removeDuplicates()
            .sink { [weak self] _ in self?.expandedLayoutChanged() }
            .store(in: &cancellables)

        model.settings.$enabledModules
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        model.settings.$collapsedLayoutMode
            .removeDuplicates()
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        model.$isPresentingSystemPermissionPrompt
            .removeDuplicates()
            .sink { [weak self] isPresenting in
                self?.systemPermissionPresentationChanged(isPresenting)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.screenConfigurationChanged() }
            .store(in: &cancellables)
    }

    private func observeForegroundApplication() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let shouldIgnoreCodexForeground = ProcessInfo.processInfo.arguments.contains("--ignore-codex-foreground")
            let shouldHide = !shouldIgnoreCodexForeground
                && CodexForegroundPolicy.shouldHide(for: app?.bundleIdentifier)
            Task { @MainActor in
                self.codexIsFrontmost = shouldHide
                if shouldHide {
                    self.hideAllPanels()
                } else {
                    self.updateVisibility()
                }
            }
        }
        codexIsFrontmost = currentAppIsCodex
    }

    private func expandedStateChanged(_ expanded: Bool) {
        guard !userHidden,
              !codexIsFrontmost,
              model.isShowingSettings || model.settings.hasEnabledModules,
              let screen = Self.notchScreen
        else {
            if !expanded { expandedPanel.orderOut(nil) }
            return
        }

        showWingPanels(on: screen)
        if expanded {
            showExpandedPanel(on: screen, animated: true)
        } else {
            hideExpandedPanel(on: screen, animated: true)
        }
    }

    private func expandedLayoutChanged() {
        guard model.isExpanded,
              !codexIsFrontmost,
              let screen = Self.notchScreen
        else { return }
        showExpandedPanel(on: screen, animated: true)
    }

    private func systemPermissionPresentationChanged(_ isPresenting: Bool) {
        if isPresenting {
            expandedPanel.level = IslandWindowLevelPolicy.whilePresentingSystemPermission
            expandedPanel.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
        } else {
            expandedPanel.level = IslandWindowLevelPolicy.normalExpanded
            if model.isExpanded, let screen = Self.notchScreen {
                showExpandedPanel(on: screen, animated: false)
            }
        }
    }

    private func screenConfigurationChanged() {
        leftWingPanel.contentView = FullBleedHostingView(
            rootView: IslandView(
                model: model,
                presentation: .leftWing
            )
        )
        rightWingPanel.contentView = FullBleedHostingView(
            rootView: IslandView(
                model: model,
                presentation: .rightWing
            )
        )
        updateVisibility()
    }

    private func showWingPanels(on screen: NSScreen) {
        positionWingPanels(on: screen)
        backdropPanel.orderFrontRegardless()
        if model.settings.isEnabled(.taskStatus) {
            leftWingPanel.orderFrontRegardless()
        } else {
            leftWingPanel.orderOut(nil)
        }

        let hasUsage = model.settings.isEnabled(.weeklyRemaining) || model.settings.isEnabled(.todayTokens)
        if hasUsage {
            rightWingPanel.orderFrontRegardless()
        } else {
            rightWingPanel.orderOut(nil)
        }
    }

    private func positionWingPanels(on screen: NSScreen) {
        let mode = model.settings.collapsedLayoutMode
        let leftWidth = CGFloat(mode.leftWingWidth)
        let rightWidth = CGFloat(mode.rightWingWidth)
        let notchEdges = TopBarGeometry.notchEdges(
            frameMidX: screen.frame.midX,
            auxiliaryLeftMaxX: screen.auxiliaryTopLeftArea?.maxX,
            auxiliaryRightMinX: screen.auxiliaryTopRightArea?.minX
        )
        let notchLeftEdge = notchEdges.left
        let notchRightEdge = notchEdges.right
        let y = screen.frame.maxY - notchBarHeight

        let hasLeft = model.settings.isEnabled(.taskStatus)
        let hasRight = model.settings.isEnabled(.weeklyRemaining) || model.settings.isEnabled(.todayTokens)
        let backdropLeft = hasLeft ? notchLeftEdge - leftWidth : notchLeftEdge
        let backdropRight = hasRight ? notchRightEdge + rightWidth : notchRightEdge
        backdropPanel.setFrame(NSRect(
            x: backdropLeft,
            y: y,
            width: backdropRight - backdropLeft,
            height: notchBarHeight
        ), display: true)

        leftWingPanel.setFrame(NSRect(
            x: notchLeftEdge - leftWidth,
            y: y,
            width: leftWidth,
            height: notchBarHeight
        ), display: true)
        rightWingPanel.setFrame(NSRect(
            x: notchRightEdge,
            y: y,
            width: rightWidth,
            height: notchBarHeight
        ), display: true)
    }

    private func showExpandedPanel(on screen: NSScreen, animated: Bool) {
        let target = expandedFrame(on: screen)
        if !expandedPanel.isVisible {
            let anchor = collapsedAnchorFrame(on: screen)
            expandedPanel.alphaValue = animated ? 0 : 1
            expandedPanel.setFrame(anchor, display: false)
            expandedPanel.orderFrontRegardless()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.72, 0.18, 1)
                expandedPanel.animator().alphaValue = 1
                expandedPanel.animator().setFrame(target, display: true)
            }
        } else {
            expandedPanel.alphaValue = 1
            expandedPanel.setFrame(target, display: true)
        }
    }

    private func hideExpandedPanel(on screen: NSScreen, animated: Bool) {
        guard expandedPanel.isVisible else { return }
        guard animated else {
            expandedPanel.orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            expandedPanel.animator().alphaValue = 0
            expandedPanel.animator().setFrame(collapsedAnchorFrame(on: screen), display: true)
        } completionHandler: { [weak expandedPanel] in
            DispatchQueue.main.async {
                expandedPanel?.orderOut(nil)
                expandedPanel?.alphaValue = 1
            }
        }
    }

    private func hideAllPanels() {
        backdropPanel.orderOut(nil)
        leftWingPanel.orderOut(nil)
        rightWingPanel.orderOut(nil)
        expandedPanel.orderOut(nil)
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let height = model.isShowingSettings ? settingsHeight : dashboardHeight
        let top = screen.frame.maxY - notchBarHeight
        return NSRect(
            x: screen.frame.midX - expandedPanelWidth / 2,
            y: top - height,
            width: expandedPanelWidth,
            height: height
        )
    }

    private func collapsedAnchorFrame(on screen: NSScreen) -> NSRect {
        let top = screen.frame.maxY - notchBarHeight
        return NSRect(
            x: screen.frame.midX - expandedPanelWidth / 2,
            y: top - 1,
            width: expandedPanelWidth,
            height: 1
        )
    }

    private static var notchScreen: NSScreen? {
        // A real notch provides exact auxiliary-area geometry. On Macs without
        // one (including many App Review and external-display setups), the
        // existing midpoint fallback presents the same controls at the top.
        NSScreen.main
    }

    private static func makeNotchBarPanel(width: CGFloat, height: CGFloat) -> NotchBarPanel {
        let panel = NotchBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.level = .screenSaver
        panel.ignoresMouseEvents = false
        return panel
    }

    private static func makeBackdropPanel(height: CGFloat) -> NotchBarPanel {
        let panel = NotchBarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        panel.ignoresMouseEvents = true
        return panel
    }

    private static func makeExpandedPanel(width: CGFloat) -> ExpandedIslandPanel {
        let panel = ExpandedIslandPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure(panel)
        panel.level = IslandWindowLevelPolicy.normalExpanded
        return panel
    }

    private static func configure(_ panel: NSPanel) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.animationBehavior = .none
    }
}

import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
private enum ApplicationInstanceGuard {
    static func shouldContinueLaunching() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return true }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let primary = running.min(by: { left, right in
            let leftDate = left.launchDate ?? .distantFuture
            let rightDate = right.launchDate ?? .distantFuture
            if leftDate != rightDate { return leftDate < rightDate }
            return left.processIdentifier < right.processIdentifier
        }), primary.processIdentifier != currentPID else {
            return true
        }
        primary.activate(options: [])
        return false
    }
}

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()
    let model = ApplicationModel()
}

@main
struct CodexIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private lazy var model = AppEnvironment.shared.model
    private var didStartModel = false
    private var islandController: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var quickNoteHotKey: GlobalHotKey?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ApplicationInstanceGuard.shouldContinueLaunching() else {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        setupMenuBar()
        islandController = IslandWindowController(model: model)
        islandController?.updateVisibility()
        quickNoteHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(cmdKey | shiftKey)
        ) { [weak self] in
            self?.islandController?.presentNewNote()
        }
        model.start()
        didStartModel = true
        if ProcessInfo.processInfo.arguments.contains("--settings-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.islandController?.showSettings()
            }
        } else if ProcessInfo.processInfo.arguments.contains("--notes-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.islandController?.showNotesWorkspace()
            }
        } else if ProcessInfo.processInfo.arguments.contains("--workspace-motion-demo") {
            islandController?.showNotesWorkspace()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.model.showActivityWorkspace()
            }
        }

        model.objectWillChange
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshMenu() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .showCodexIslandSettings)
            .sink { [weak self] _ in self?.islandController?.showSettings() }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if didStartModel { model.stop() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "Halofold")
        item.button?.image?.isTemplate = true
        item.menu = NSMenu()
        item.menu?.delegate = self
        statusItem = item
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        let summary = NSMenuItem(
            title: AppLocalization.format(
                "运行中 %lld   完成 %lld   中断 %lld",
                Int64(model.runningCount), Int64(model.completedCount), Int64(model.pausedCount)
            ),
            action: nil,
            keyEquivalent: ""
        )
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
        let newNote = menu.addItem(withTitle: AppLocalization.text("新建便签"), action: #selector(newNoteAction), keyEquivalent: " ")
        newNote.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(withTitle: AppLocalization.text(model.isExpanded ? "收起灵动岛" : "展开灵动岛"), action: #selector(toggleExpanded), keyEquivalent: "")
        menu.addItem(withTitle: AppLocalization.text("显示 / 隐藏灵动岛"), action: #selector(toggleIslandVisibility), keyEquivalent: "")
        menu.addItem(withTitle: AppLocalization.text("设置…"), action: #selector(showSettingsAction), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: AppLocalization.text("退出 Halofold"), action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
    }

    @objc private func toggleExpanded() {
        model.toggleExpanded()
        islandController?.updateVisibility()
    }

    @objc private func newNoteAction() {
        islandController?.presentNewNote()
    }

    @objc private func toggleIslandVisibility() { islandController?.toggleUserVisibility() }
    @objc private func showSettingsAction() { islandController?.showSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}

from pathlib import Path
import shutil, json, hashlib, subprocess
root=Path(__file__).resolve().parents[3]
out=Path(__file__).resolve().parents[1]
work=Path('/tmp/halofold-ui-upgrade-capture')
work.mkdir(exist_ok=True)
for name in ['Sources','Resources']:
 if (root/name).exists(): shutil.copytree(root/name,work/name,dirs_exist_ok=True)
shutil.copy2(root/'Package.swift',work/'Package.swift')
(work/'Tests/CodexIslandTests').mkdir(parents=True,exist_ok=True)
src=work/'Sources/CodexIsland'
def edit(rel, old, new):
 p=src/rel; s=p.read_text(); assert old in s, (rel,old); p.write_text(s.replace(old,new,1))
# Capture-only state fixtures; the product checkout is never patched.
edit('Core/ApplicationModel.swift','self.notes = NoteLibraryModel()','self.notes = NoteLibraryModel(demoMode: true)')
with (src/'Core/ApplicationModel.swift').open('a') as f: f.write('''
@MainActor extension ApplicationModel {
    func atlasConfigure(_ scenario: String) {
        loadDemoData()
        expandedWorkspace = .activity
        hasCodexFolderAccess = true
        isExpanded = true
        isShowingSettings = scenario.hasPrefix("settings-")
        if scenario.hasPrefix("notes-") { expandedWorkspace = .notes }
        if scenario.hasPrefix("schedule-") { expandedWorkspace = .schedule }
        if ["activity-completed", "activity-paused", "activity-action", "activity-summary"].contains(scenario) { conversations.removeAll { $0.state == .running } }
        if scenario == "activity-empty" { conversations = [] }
        if scenario == "activity-warning" { setSourceMessage("无法连接 Codex 本地数据，请检查访问授权", warning: true) }
        if scenario == "settings-permission" { hasCodexFolderAccess = false }
    }
}
''')
edit('UI/IslandView.swift','ProcessInfo.processInfo.arguments.contains("--completed-list-demo") ? .completed : nil','Atlas.scenario == "activity-completed" ? .completed : (Atlas.scenario == "activity-paused" ? .paused : (Atlas.scenario == "activity-action" ? .needsAction : nil))')
edit('UI/SettingsView.swift','_settings = ObservedObject(wrappedValue: model.settings)','''_settings = ObservedObject(wrappedValue: model.settings)
        let suffix = Atlas.scenario.replacingOccurrences(of: "settings-", with: "")
        if let section = SettingsSection(rawValue: suffix) { _selection = State(initialValue: section) }
''')
edit('UI/SettingsView.swift', '.sheet(isPresented: $isShowingPrivacyPolicy) {', '.onAppear { if Atlas.scenario == "settings-privacy" { isShowingPrivacyPolicy = true } }\n        .sheet(isPresented: $isShowingPrivacyPolicy) {')
edit('UI/SettingsView.swift', '.sheet(item: $funVoiceTarget) { target in', '.onAppear { if Atlas.scenario == "settings-funvoice" { funVoiceTarget = FunVoiceTarget(kind: .completed) } }\n        .sheet(item: $funVoiceTarget) { target in')
edit('UI/SettingsView.swift', 'let suffix = Atlas.scenario.replacingOccurrences(of: "settings-", with: "")', 'let suffix = Atlas.scenario == "settings-funvoice" ? "voice" : (Atlas.scenario == "settings-privacy" ? "general" : Atlas.scenario.replacingOccurrences(of: "settings-", with: ""))')
# onAppear uses real view actions so initialization and form logic match the app.
edit('UI/ScheduleWorkspaceView.swift','.sheet(isPresented: $isShowingTimeAdjustment) {','''.onAppear {
            switch Atlas.scenario {
            case "schedule-new": beginAdding()
            case "schedule-new-filled": beginAdding(); draftTitle = "整理本周产品反馈"
            case "schedule-edit": if let item = schedule.occurrences(on: schedule.selectedDate).first { beginEditing(item, scope: .thisOccurrence) }
            case "schedule-adjust": if let item = schedule.occurrences(on: schedule.selectedDate).first { editingOccurrenceID = item.id; adjustmentStart = item.plannedStart; isShowingTimeAdjustment = true }
            case "schedule-routine": selectedTab = .routine
            case "schedule-routine-new": selectedTab = .routine; beginAddingRoutine()
            case "schedule-routine-daily": selectedTab = .routine; beginAddingRoutine(); routineDraftTitle = "回顾今天的工作"; routineDraftStyle = .dailyTime
            case "schedule-routine-edit": selectedTab = .routine; if let item = schedule.snapshot.routines.first(where: { $0.kind == .custom }) { beginEditingRoutine(item) }
            default: break
            }
        }
        .sheet(isPresented: $isShowingTimeAdjustment) {''')
# Use a distinct executable bundle plus explicit defaults suite.
(src/'AppDelegate.swift').write_text('''import AppKit
import SwiftUI
import Foundation

enum Atlas {
    static let scenario = ProcessInfo.processInfo.environment["ATLAS_SCENARIO"] ?? "activity-main"
}
@main struct AtlasMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AtlasDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}
@MainActor final class AtlasWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }
@MainActor final class AtlasDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var model: ApplicationModel!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let prefs = UserDefaults(suiteName: "local.halofold.ui-atlas.fixtures")!
        model = ApplicationModel(settings: AppSettings(defaults: prefs))
        model.atlasConfigure(Atlas.scenario)
        if Atlas.scenario == "notes-new" { model.notes.createNote() }
        if Atlas.scenario == "notes-many" {
            for title in ["一个较长的便签标题：产品交互体验与视觉改进计划", "设计参考", "灵感收集", "待办事项", "会议记录", "下周安排"] { model.notes.createNote(title: title) }
        }
        let schedule = model.schedule
        let now = Date()
        if Atlas.scenario.hasPrefix("schedule-"), Atlas.scenario != "schedule-empty", Atlas.scenario != "schedule-new", Atlas.scenario != "schedule-new-filled" {
            let item = schedule.add(title: "整理本周产品反馈", plannedStart: now.addingTimeInterval(1800), durationMinutes: 45)
            schedule.add(title: "阅读与学习", plannedStart: now.addingTimeInterval(5400), durationMinutes: 30, repeatRule: .weekly)
            schedule.addCustomRoutine(title: "回顾今天的工作", reminderStyle: .dailyTime, dailyTimeMinutes: 1260)
            switch Atlas.scenario {
            case "schedule-awaiting": schedule.markAwaitingStart(item.id)
            case "schedule-overdue", "schedule-adjust": schedule.markAwaitingStart(item.id); schedule.markOverdueDecision(item.id)
            case "schedule-running": schedule.start(item.id, at: now.addingTimeInterval(-300))
            case "schedule-completed": schedule.start(item.id, at: now.addingTimeInterval(-2700)); schedule.complete(item.id)
            default: break
            }
        }
        var content: AnyView
        if Atlas.scenario.hasPrefix("collapsed-") {
            model.settings.collapsedLayoutMode = Atlas.scenario == "collapsed-compact" ? .compact : .relaxed
            content = AnyView(HStack(spacing: 0) {
                IslandView(model: model, presentation: .leftWing)
                Color.black.frame(width: 185, height: 32)
                IslandView(model: model, presentation: .rightWing)
            }.fixedSize().padding(12))
        } else {
            content = AnyView(IslandView(model: model, presentation: .expandedContent).padding(12))
        }
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        window = AtlasWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "Halofold UI Atlas"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.addObserver(forName: .showCodexIslandSettings, object: nil, queue: .main) { [weak self] _ in self?.model.showSettings() }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [self] in
            let path = ProcessInfo.processInfo.environment["ATLAS_READY"]!
            let info: [String: Any] = ["windowID": window.attachedSheet?.windowNumber ?? window.windowNumber, "scenario": Atlas.scenario, "width": window.frame.width, "height": window.frame.height]
            let data = try! JSONSerialization.data(withJSONObject: info)
            try! data.write(to: URL(fileURLWithPath: path))
        }
    }
}
''')
manifest={'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'sourceStatus':subprocess.check_output(['git','status','--short'],cwd=root,text=True),'files':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/'Sources').rglob('*') if p.is_file()},'captureMethod':'Original native SwiftUI/AppKit views in isolated native window; state fixtures only in /tmp copy. Screen capture, not design redraw. Window position centered for capture; real notch placement not validated.','compileFlag':'HALOFOLD_NO_CODEX_TODO','dataRoot':'per-scenario temporary directories','workingCopy':str(work)}
(out/'source-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2))
print(work)

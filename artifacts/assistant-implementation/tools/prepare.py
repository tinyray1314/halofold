from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[3]
work=Path('/tmp/halofold-assistant-check')
work.mkdir(exist_ok=True)
shutil.copytree(root/'Sources',work/'Sources',dirs_exist_ok=True)
shutil.copy2(root/'Package.swift',work/'Package.swift')
(work/'Tests/CodexIslandTests').mkdir(parents=True,exist_ok=True)
(work/'Sources/CodexIsland/AppDelegate.swift').write_text('''import AppKit
import SwiftUI
@main struct CheckMain {
 @MainActor static func main() {
  let app = NSApplication.shared
  let delegate = CheckDelegate()
  app.delegate = delegate
  app.run()
  _ = delegate
 }
}
@MainActor final class CheckDelegate: NSObject, NSApplicationDelegate {
 var controller: IslandWindowController!
 var model: ApplicationModel!
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.regular)
  model = ApplicationModel(settings: AppSettings(defaults: UserDefaults(suiteName: "local.halofold.assistant-check.fixtures")!))
  model.enterDemoMode()
  let id = model.notes.selectedNoteID!
  model.notes.updateTitle("产品设计想法", for: id)
  model.notes.updateBody(NoteContent.demoRTF(), for: id)
  model.notes.createNote(title: "本周待办")
  model.notes.select(model.notes.notes.first { $0.id == id }!)
  let item = model.schedule.add(title: "整理产品设计思路", plannedStart: Date(), durationMinutes: 30)
  model.schedule.start(item.id, at: Date().addingTimeInterval(-300))
  model.schedule.add(title: "阅读与学习", plannedStart: Date().addingTimeInterval(3600), durationMinutes: 30)
  controller = IslandWindowController(model: model)
  model.showQuickPanel()
  controller.updateVisibility()
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.model.expandNoteEditor() }
  NSApp.activate(ignoringOtherApps: true)
 }
}
''')
print(work)

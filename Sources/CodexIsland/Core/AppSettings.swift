import AVFoundation
import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let enabledModules = "enabledModules.v1"
        static let moduleOrder = "moduleOrder.v1"
        static let collapsedLayoutMode = "collapsedLayoutMode.v1"
        static let completionEnabled = "completionEnabled"
        static let pauseEnabled = "pauseEnabled"
        static let completionMode = "completionMode"
        static let pauseMode = "pauseMode"
        static let completionText = "completionText"
        static let pauseText = "pauseText"
        static let completionTextCustomized = "completionTextCustomized.v1"
        static let pauseTextCustomized = "pauseTextCustomized.v1"
        static let voiceIdentifier = "voiceIdentifier"
        static let voiceVolume = "voiceVolume"
        static let completionAudio = "completionAudio"
        static let pauseAudio = "pauseAudio"
    }

    private let defaults: UserDefaults
    private var isLoading = true
    private var completionTextCustomized = false
    private var pauseTextCustomized = false

    @Published var enabledModules: Set<DisplayModule> = Set(DisplayModule.allCases) { didSet { save() } }
    @Published var moduleOrder: [DisplayModule] = DisplayModule.allCases { didSet { save() } }
    @Published var collapsedLayoutMode: CollapsedLayoutMode = .compact { didSet { save() } }
    @Published var completionEnabled = true { didSet { save() } }
    @Published var pauseEnabled = true { didSet { save() } }
    @Published var completionMode: VoiceMode = .system { didSet { save() } }
    @Published var pauseMode: VoiceMode = .system { didSet { save() } }
    @Published var completionText = AppLocalization.defaultCompletionText {
        didSet {
            if !isLoading { completionTextCustomized = true }
            save()
        }
    }
    @Published var pauseText = AppLocalization.defaultPauseText {
        didSet {
            if !isLoading { pauseTextCustomized = true }
            save()
        }
    }
    @Published var voiceIdentifier = "" { didSet { save() } }
    @Published var voiceVolume: Double = 0.82 { didSet { save() } }
    @Published var completionAudioPath: String? { didSet { save() } }
    @Published var pauseAudioPath: String? { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateLegacyPreferencesIfNeeded()
        load()
        if ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.environment["CODEX_ISLAND_DEMO"] == "1" {
            enabledModules = Set(DisplayModule.allCases)
            moduleOrder = DisplayModule.allCases
        }
        if ProcessInfo.processInfo.arguments.contains("--compact-demo") {
            collapsedLayoutMode = .compact
        } else if ProcessInfo.processInfo.arguments.contains("--relaxed-demo") {
            collapsedLayoutMode = .relaxed
        }
        isLoading = false
    }

    private func migrateLegacyPreferencesIfNeeded() {
        guard defaults === UserDefaults.standard,
              defaults.object(forKey: Key.moduleOrder) == nil,
              let legacy = UserDefaults(suiteName: "com.tinyray.codexisland")
        else { return }
        let keys = [
            Key.enabledModules, Key.moduleOrder, Key.collapsedLayoutMode,
            Key.completionEnabled, Key.pauseEnabled, Key.completionMode,
            Key.pauseMode, Key.completionText, Key.pauseText,
            Key.completionTextCustomized, Key.pauseTextCustomized,
            Key.voiceIdentifier, Key.voiceVolume, Key.completionAudio,
            Key.pauseAudio
        ]
        for key in keys where defaults.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }

    var hasEnabledModules: Bool { !enabledModules.isEmpty }

    func isEnabled(_ module: DisplayModule) -> Bool { enabledModules.contains(module) }

    func setEnabled(_ module: DisplayModule, enabled: Bool) {
        if enabled { enabledModules.insert(module) } else { enabledModules.remove(module) }
    }

    func moveModules(from offsets: IndexSet, to destination: Int) {
        moduleOrder.move(fromOffsets: offsets, toOffset: destination)
    }

    func moveModule(_ module: DisplayModule, direction: Int) {
        guard let index = moduleOrder.firstIndex(of: module) else { return }
        let destination = index + direction
        guard moduleOrder.indices.contains(destination) else { return }
        moduleOrder.swapAt(index, destination)
    }

    func moveModule(_ source: DisplayModule, before destination: DisplayModule) {
        guard source != destination,
              let sourceIndex = moduleOrder.firstIndex(of: source),
              let destinationIndex = moduleOrder.firstIndex(of: destination)
        else { return }
        moduleOrder.remove(at: sourceIndex)
        let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
        moduleOrder.insert(source, at: adjustedDestination)
    }

    var selectedVoice: AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier),
           voice.language.hasPrefix(AppLocalization.voiceLanguagePrefix) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: AppLocalization.defaultVoiceLanguage)
    }

    private func load() {
        if let raw = defaults.array(forKey: Key.enabledModules) as? [String] {
            enabledModules = Set(raw.compactMap(DisplayModule.init(rawValue:)))
        }
        if let raw = defaults.array(forKey: Key.moduleOrder) as? [String] {
            let saved = raw.compactMap(DisplayModule.init(rawValue:))
            let missing = DisplayModule.allCases.filter { !saved.contains($0) }
            moduleOrder = saved + missing
        }
        collapsedLayoutMode = defaults.string(forKey: Key.collapsedLayoutMode)
            .flatMap(CollapsedLayoutMode.init(rawValue:)) ?? .compact
        if defaults.object(forKey: Key.completionEnabled) != nil {
            completionEnabled = defaults.bool(forKey: Key.completionEnabled)
        }
        if defaults.object(forKey: Key.pauseEnabled) != nil {
            pauseEnabled = defaults.bool(forKey: Key.pauseEnabled)
        }
        completionMode = defaults.string(forKey: Key.completionMode).flatMap(VoiceMode.init(rawValue:)) ?? .system
        pauseMode = defaults.string(forKey: Key.pauseMode).flatMap(VoiceMode.init(rawValue:)) ?? .system
        let legacyCompletionDefaults = ["有 {count} 个 Codex 任务已完成"]
        let legacyPauseDefaults = ["有 {count} 个 Codex 任务已暂停", "有 {count} 个 Codex 任务已中断"]
        let storedCompletion = defaults.string(forKey: Key.completionText)
        let storedPause = defaults.string(forKey: Key.pauseText)
        completionTextCustomized = defaults.object(forKey: Key.completionTextCustomized) != nil
            ? defaults.bool(forKey: Key.completionTextCustomized)
            : storedCompletion.map { !legacyCompletionDefaults.contains($0) } ?? false
        pauseTextCustomized = defaults.object(forKey: Key.pauseTextCustomized) != nil
            ? defaults.bool(forKey: Key.pauseTextCustomized)
            : storedPause.map { !legacyPauseDefaults.contains($0) } ?? false
        completionText = completionTextCustomized ? (storedCompletion ?? AppLocalization.defaultCompletionText) : AppLocalization.defaultCompletionText
        pauseText = pauseTextCustomized ? (storedPause ?? AppLocalization.defaultPauseText) : AppLocalization.defaultPauseText
        let languageVoiceKey = "\(Key.voiceIdentifier).\(AppLocalization.languageCode)"
        if let languageVoice = defaults.string(forKey: languageVoiceKey) {
            voiceIdentifier = languageVoice
        } else if AppLocalization.languageCode == "zh-Hans" {
            voiceIdentifier = defaults.string(forKey: Key.voiceIdentifier) ?? ""
        }
        if defaults.object(forKey: Key.voiceVolume) != nil {
            voiceVolume = defaults.double(forKey: Key.voiceVolume)
        }
        completionAudioPath = defaults.string(forKey: Key.completionAudio)
        pauseAudioPath = defaults.string(forKey: Key.pauseAudio)
    }

    private func save() {
        guard !isLoading else { return }
        defaults.set(enabledModules.map(\.rawValue), forKey: Key.enabledModules)
        defaults.set(moduleOrder.map(\.rawValue), forKey: Key.moduleOrder)
        defaults.set(collapsedLayoutMode.rawValue, forKey: Key.collapsedLayoutMode)
        defaults.set(completionEnabled, forKey: Key.completionEnabled)
        defaults.set(pauseEnabled, forKey: Key.pauseEnabled)
        defaults.set(completionMode.rawValue, forKey: Key.completionMode)
        defaults.set(pauseMode.rawValue, forKey: Key.pauseMode)
        defaults.set(completionText, forKey: Key.completionText)
        defaults.set(pauseText, forKey: Key.pauseText)
        defaults.set(completionTextCustomized, forKey: Key.completionTextCustomized)
        defaults.set(pauseTextCustomized, forKey: Key.pauseTextCustomized)
        defaults.set(voiceIdentifier, forKey: "\(Key.voiceIdentifier).\(AppLocalization.languageCode)")
        defaults.set(voiceVolume, forKey: Key.voiceVolume)
        defaults.set(completionAudioPath, forKey: Key.completionAudio)
        defaults.set(pauseAudioPath, forKey: Key.pauseAudio)
    }
}

private extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { self[$0] }
        let remaining = enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let adjusted = destination - source.filter { $0 < destination }.count
        self = Array(remaining.prefix(adjusted)) + moving + Array(remaining.dropFirst(adjusted))
    }
}

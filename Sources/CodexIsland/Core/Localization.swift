import Foundation

enum AppLocalization {
    static let bundle = Bundle.main

    static var languageCode: String {
        let code = bundle.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "zh-Hans"
        return code.hasPrefix("en") ? "en" : "zh-Hans"
    }

    static var speechLocale: Locale {
        Locale(identifier: languageCode == "en" ? "en_US" : "zh_CN")
    }

    static var voiceLanguagePrefix: String { languageCode == "en" ? "en" : "zh" }
    static var defaultVoiceLanguage: String { languageCode == "en" ? "en-US" : "zh-CN" }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: "")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    static var defaultCompletionText: String { text("有 {count} 个 Codex 任务已完成") }
    static var defaultPauseText: String { text("有 {count} 个 Codex 任务已中断") }
}

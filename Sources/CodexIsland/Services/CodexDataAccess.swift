import AppKit
import Foundation

enum CodexDataAccessError: LocalizedError {
    case invalidFolder
    case bookmarkCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidFolder: return AppLocalization.text("请选择包含 state_5.sqlite 的 .codex 文件夹")
        case .bookmarkCreationFailed: return AppLocalization.text("无法保存该文件夹的长期只读授权")
        }
    }
}

/// Owns the security-scoped bookmark required by Mac App Store sandbox builds.
/// Non-sandboxed development builds keep the existing zero-setup ~/.codex behavior.
final class CodexDataAccess {
    static let shared = CodexDataAccess()

    private let bookmarkKey = "codexDirectoryBookmark.v1"
    private var scopedURL: URL?

    var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    var codexDirectory: URL? {
        if let scopedURL { return scopedURL }
        if !isSandboxed {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        }
        return nil
    }

    private init() {
        migrateLegacyBookmarkIfNeeded()
        restoreBookmark()
    }

    deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    @MainActor
    func requestAccess() throws -> URL? {
        let panel = NSOpenPanel()
        panel.title = AppLocalization.text("选择 Codex 数据文件夹")
        panel.message = AppLocalization.text("请选择个人目录中的 .codex 文件夹。应用以只读方式处理任务状态、用量和对话正文；对话仅在本机用于发现待办，不会上传或读取登录凭据。")
        panel.prompt = AppLocalization.text("授权只读访问")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        try authorize(url)
        return url
    }

    func authorize(_ url: URL) throws {
        let standardized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: standardized.appendingPathComponent("state_5.sqlite").path) else {
            throw CodexDataAccessError.invalidFolder
        }
        let data = try standardized.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        guard !data.isEmpty else { throw CodexDataAccessError.bookmarkCreationFailed }
        scopedURL?.stopAccessingSecurityScopedResource()
        guard standardized.startAccessingSecurityScopedResource() else {
            throw CodexDataAccessError.bookmarkCreationFailed
        }
        scopedURL = standardized
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    private func restoreBookmark() {
        guard isSandboxed, let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), url.startAccessingSecurityScopedResource() else { return }
        scopedURL = url
        if stale, let refreshed = try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
    }

    private func migrateLegacyBookmarkIfNeeded() {
        guard UserDefaults.standard.data(forKey: bookmarkKey) == nil,
              let legacy = UserDefaults(suiteName: "com.tinyray.codexisland"),
              let data = legacy.data(forKey: bookmarkKey)
        else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }
}

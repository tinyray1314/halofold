import AppKit
import Foundation

enum NoteTypography {
    static let title: CGFloat = 21
    static let heading: CGFloat = 19
    static let body: CGFloat = 15
}

struct NoteDocument: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var bodyRTF: Data
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        bodyRTF: Data = NoteContent.emptyRTF,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.bodyRTF = bodyRTF
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppLocalization.text("未命名便签") : trimmed
    }

    var openTaskCount: Int {
        NoteContent.plainText(from: bodyRTF)
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("☐") }
            .count
    }
}

struct NoteLibrarySnapshot: Codable, Equatable, Sendable {
    var notes: [NoteDocument]
    var selectedNoteID: UUID?
}

enum NoteContent {
    private static let bodyFont = NSFont.systemFont(ofSize: NoteTypography.body)

    static var emptyRTF: Data {
        rtf(from: NSAttributedString(string: "", attributes: baseAttributes))
    }

    static func plainText(from data: Data) -> String {
        attributedString(from: data).string
    }

    static func attributedString(from data: Data) -> NSAttributedString {
        let attributedString = (try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )) ?? NSAttributedString(string: "", attributes: baseAttributes)
        return normalizedForDarkEditor(normalizedTypography(attributedString))
    }

    static func rtf(from attributedString: NSAttributedString) -> Data {
        (try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }

    static func appendingTasks(_ tasks: [String], to data: Data) -> Data {
        guard !tasks.isEmpty else { return data }
        let result = NSMutableAttributedString(attributedString: attributedString(from: data))
        if result.length > 0, !result.string.hasSuffix("\n") {
            append("\n", to: result)
        }
        for (index, task) in tasks.enumerated() {
            append("☐ \(task)", to: result)
            if index < tasks.count - 1 { append("\n", to: result) }
        }
        return rtf(from: result)
    }

    static func demoRTF() -> Data {
        let result = NSMutableAttributedString()
        append("在不打断当前工作流的前提下，提供随时召唤的快速记录能力，让灵感、待办与想法一闪即记、轻松切换、随时可查。\n\n", to: result)
        append("核心原则：快速捕捉，专注思考，零干扰。\n\n", to: result, bold: true)
        append("真正的效率，来自于在正确的时刻，记录正确的想法。\n— Halofold 设计信条\n\n", to: result, quote: true)
        append("• 从任何界面，通过快捷键召唤\n", to: result)
        append("• 横向切换便签，轻量、快速\n", to: result)
        append("• 本地优先，自动保存，隐私安全\n\n", to: result)
        append("1. 快速记录灵感\n", to: result)
        append("2. 整理与深化想法\n", to: result)
        append("3. 行动与复盘\n\n", to: result)
        append("☑ 完善快捷召唤体验\n", to: result, completedTask: true)
        append("☑ 优化横向切换与新建流程\n", to: result, completedTask: true)
        append("☑ 补充键盘导航与快捷键提示\n", to: result, completedTask: true)
        append("☐ 撰写功能介绍文案", to: result)
        return rtf(from: result)
    }

    private static var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        paragraph.paragraphSpacing = 3
        return [
            .font: bodyFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.88),
            .paragraphStyle: paragraph
        ]
    }

    private static func normalizedTypography(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? NSFont,
                  abs(font.pointSize - 21) < 0.25,
                  let normalized = NSFont(descriptor: font.fontDescriptor, size: NoteTypography.heading)
            else { return }
            result.addAttribute(.font, value: normalized, range: range)
        }
        return result
    }

    static func normalizedPastedContent(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: result.length)
        guard fullRange.length > 0 else { return result }
        result.removeAttribute(.backgroundColor, range: fullRange)
        result.removeAttribute(.strokeColor, range: fullRange)
        result.addAttribute(
            .foregroundColor,
            value: NSColor.white.withAlphaComponent(0.88),
            range: fullRange
        )
        return normalizedTypography(result)
    }

    private static func normalizedForDarkEditor(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: result.length)
        guard fullRange.length > 0 else { return result }
        result.removeAttribute(.backgroundColor, range: fullRange)
        result.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
            guard let color = value as? NSColor,
                  let rgb = color.usingColorSpace(.deviceRGB)
            else { return }
            let luminance = 0.2126 * rgb.redComponent
                + 0.7152 * rgb.greenComponent
                + 0.0722 * rgb.blueComponent
            if luminance < 0.52 {
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.white.withAlphaComponent(0.88),
                    range: range
                )
            }
        }
        return result
    }

    private static func append(
        _ string: String,
        to result: NSMutableAttributedString,
        bold: Bool = false,
        quote: Bool = false,
        completedTask: Bool = false
    ) {
        var attributes = baseAttributes
        if bold {
            attributes[.font] = NSFont.systemFont(ofSize: NoteTypography.body, weight: .semibold)
        }
        if quote {
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = 18
            paragraph.firstLineHeadIndent = 18
            paragraph.tailIndent = -10
            paragraph.lineSpacing = 5
            paragraph.paragraphSpacing = 4
            attributes[.paragraphStyle] = paragraph
            attributes[.foregroundColor] = NSColor.white.withAlphaComponent(0.66)
            attributes[.font] = NSFont.systemFont(ofSize: 14.5).italic()
        }
        if completedTask {
            attributes[.foregroundColor] = NSColor.white.withAlphaComponent(0.55)
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        result.append(NSAttributedString(string: string, attributes: attributes))
    }
}

private extension NSFont {
    func italic() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }
}

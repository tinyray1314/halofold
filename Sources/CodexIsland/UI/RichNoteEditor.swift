import AppKit
import SwiftUI

enum RichTextCommandKind {
    case heading
    case bold
    case quote
    case bulletList
    case numberedList
    case taskList
}

struct RichTextCommand: Equatable {
    let id = UUID()
    let kind: RichTextCommandKind
}

struct RichNoteEditor: NSViewRepresentable {
    let documentID: UUID
    let rtfData: Data
    let command: RichTextCommand?
    let focusRequestID: UUID?
    let onChange: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = RichNoteTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = NSColor.white.withAlphaComponent(0.88)
        textView.insertionPointColor = .white
        textView.font = .systemFont(ofSize: NoteTypography.body)
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.textStorage?.setAttributedString(NoteContent.attributedString(from: rtfData))
        textView.onCheckboxClick = { [weak textView] characterIndex in
            guard let textView else { return }
            context.coordinator.toggleTask(at: characterIndex, in: textView)
        }
        context.coordinator.documentID = documentID
        context.coordinator.lastAppliedData = rtfData
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? RichNoteTextView else { return }
        context.coordinator.parent = self

        if context.coordinator.documentID != documentID {
            context.coordinator.flush(textView)
            context.coordinator.isApplyingExternalChange = true
            textView.textStorage?.setAttributedString(NoteContent.attributedString(from: rtfData))
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            context.coordinator.isApplyingExternalChange = false
            context.coordinator.documentID = documentID
            context.coordinator.lastAppliedData = rtfData
        } else if context.coordinator.lastAppliedData != rtfData,
                  !context.coordinator.isEditing {
            context.coordinator.isApplyingExternalChange = true
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(NoteContent.attributedString(from: rtfData))
            textView.setSelectedRange(NSRange(location: min(selection.location, textView.string.utf16.count), length: 0))
            context.coordinator.isApplyingExternalChange = false
            context.coordinator.lastAppliedData = rtfData
        }

        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.kind, to: textView)
        }

        if let focusRequestID, context.coordinator.lastFocusRequestID != focusRequestID {
            context.coordinator.lastFocusRequestID = focusRequestID
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? RichNoteTextView else { return }
        coordinator.flush(textView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichNoteEditor
        var documentID: UUID?
        var lastAppliedData = Data()
        var lastCommandID: UUID?
        var lastFocusRequestID: UUID?
        var isApplyingExternalChange = false
        var isEditing = false
        private var emitWorkItem: DispatchWorkItem?

        init(parent: RichNoteEditor) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let textView = notification.object as? NSTextView else { return }
            flush(textView)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalChange,
                  let textView = notification.object as? NSTextView
            else { return }
            scheduleEmit(textView)
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            return continueListIfNeeded(in: textView)
        }

        func apply(_ command: RichTextCommandKind, to textView: NSTextView) {
            switch command {
            case .heading:
                toggleHeading(in: textView)
            case .bold:
                toggleBold(in: textView)
            case .quote:
                toggleQuote(in: textView)
            case .bulletList:
                toggleList(prefix: "• ", in: textView)
            case .numberedList:
                toggleNumberedList(in: textView)
            case .taskList:
                toggleList(prefix: "☐ ", alternatePrefixes: ["☑ "], in: textView)
            }
            textView.window?.makeFirstResponder(textView)
            textView.didChangeText()
        }

        func toggleTask(at index: Int, in textView: NSTextView) {
            let source = textView.string as NSString
            guard index < source.length else { return }
            let value = source.substring(with: NSRange(location: index, length: 1))
            guard value == "☐" || value == "☑" else { return }
            let replacement = value == "☐" ? "☑" : "☐"
            let lineRange = source.lineRange(for: NSRange(location: index, length: 0))
            textView.textStorage?.replaceCharacters(in: NSRange(location: index, length: 1), with: replacement)
            let contentRange = NSRange(location: lineRange.location, length: max(0, min(lineRange.length, textView.string.utf16.count - lineRange.location)))
            if replacement == "☑" {
                textView.textStorage?.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.55)
                ], range: contentRange)
            } else {
                textView.textStorage?.removeAttribute(.strikethroughStyle, range: contentRange)
                textView.textStorage?.addAttribute(.foregroundColor, value: NSColor.white.withAlphaComponent(0.88), range: contentRange)
            }
            textView.didChangeText()
        }

        func flush(_ textView: NSTextView) {
            emitWorkItem?.cancel()
            emitWorkItem = nil
            emit(textView)
        }

        private func scheduleEmit(_ textView: NSTextView) {
            emitWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.emit(textView)
            }
            emitWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
        }

        private func emit(_ textView: NSTextView) {
            let data = NoteContent.rtf(from: textView.attributedString())
            lastAppliedData = data
            parent.onChange(data)
        }

        private func targetParagraphRange(in textView: NSTextView) -> NSRange {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            guard source.length > 0 else { return NSRange(location: 0, length: 0) }
            let safeLocation = min(selection.location, source.length - 1)
            let safeLength = min(selection.length, source.length - safeLocation)
            return source.paragraphRange(for: NSRange(location: safeLocation, length: safeLength))
        }

        private func toggleBold(in textView: NSTextView) {
            let selection = textView.selectedRange()
            let target = selection.length > 0 ? selection : targetParagraphRange(in: textView)
            guard target.length > 0 else {
                var attributes = textView.typingAttributes
                let font = (attributes[.font] as? NSFont) ?? .systemFont(ofSize: NoteTypography.body)
                let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
                attributes[.font] = NSFontManager.shared.convert(font, toNotHaveTrait: isBold ? .boldFontMask : [])
                if !isBold { attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                textView.typingAttributes = attributes
                return
            }
            let font = (textView.textStorage?.attribute(.font, at: target.location, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: NoteTypography.body)
            let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            textView.textStorage?.enumerateAttribute(.font, in: target) { value, range, _ in
                let current = (value as? NSFont) ?? .systemFont(ofSize: NoteTypography.body)
                let converted = isBold
                    ? NSFontManager.shared.convert(current, toNotHaveTrait: .boldFontMask)
                    : NSFontManager.shared.convert(current, toHaveTrait: .boldFontMask)
                textView.textStorage?.addAttribute(.font, value: converted, range: range)
            }
        }

        private func toggleHeading(in textView: NSTextView) {
            let target = targetParagraphRange(in: textView)
            guard target.length > 0 else { return }
            let font = (textView.textStorage?.attribute(.font, at: target.location, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: NoteTypography.body)
            let isHeading = font.pointSize >= NoteTypography.heading
            let next = isHeading
                ? NSFont.systemFont(ofSize: NoteTypography.body)
                : NSFont.systemFont(ofSize: NoteTypography.heading, weight: .semibold)
            textView.textStorage?.addAttribute(.font, value: next, range: target)
        }

        private func toggleQuote(in textView: NSTextView) {
            let target = targetParagraphRange(in: textView)
            guard target.length > 0 else { return }
            let existing = (textView.textStorage?.attribute(.paragraphStyle, at: target.location, effectiveRange: nil) as? NSParagraphStyle)
            let isQuote = (existing?.headIndent ?? 0) >= 12
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 5
            paragraph.paragraphSpacing = 4
            if !isQuote {
                paragraph.headIndent = 18
                paragraph.firstLineHeadIndent = 18
                paragraph.tailIndent = -10
            }
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: target)
            textView.textStorage?.addAttribute(
                .foregroundColor,
                value: NSColor.white.withAlphaComponent(isQuote ? 0.88 : 0.66),
                range: target
            )
        }

        private func toggleList(prefix: String, alternatePrefixes: [String] = [], in textView: NSTextView) {
            let target = targetParagraphRange(in: textView)
            let source = textView.string as NSString
            guard target.location <= source.length else { return }
            let paragraphRanges = paragraphRanges(in: target, source: source)
            let accepted = [prefix] + alternatePrefixes
            let allPrefixed = paragraphRanges.allSatisfy { range in
                let line = source.substring(with: range)
                return accepted.contains(where: line.hasPrefix)
            }
            for range in paragraphRanges.reversed() {
                let line = (textView.string as NSString).substring(with: range)
                if allPrefixed, let matched = accepted.first(where: line.hasPrefix) {
                    textView.textStorage?.replaceCharacters(in: NSRange(location: range.location, length: (matched as NSString).length), with: "")
                } else if !accepted.contains(where: line.hasPrefix) {
                    textView.textStorage?.insert(NSAttributedString(string: prefix, attributes: textView.typingAttributes), at: range.location)
                }
            }
        }

        private func toggleNumberedList(in textView: NSTextView) {
            let target = targetParagraphRange(in: textView)
            let source = textView.string as NSString
            let ranges = paragraphRanges(in: target, source: source)
            let pattern = try? NSRegularExpression(pattern: #"^\d+\.\s"#)
            let allNumbered = ranges.allSatisfy { range in
                let line = source.substring(with: range)
                return pattern?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
            }
            for (offset, range) in ranges.enumerated().reversed() {
                let currentSource = textView.string as NSString
                let line = currentSource.substring(with: range)
                if allNumbered,
                   let match = pattern?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                    textView.textStorage?.replaceCharacters(in: NSRange(location: range.location, length: match.range.length), with: "")
                } else {
                    textView.textStorage?.insert(NSAttributedString(string: "\(offset + 1). ", attributes: textView.typingAttributes), at: range.location)
                }
            }
        }

        private func paragraphRanges(in target: NSRange, source: NSString) -> [NSRange] {
            var ranges: [NSRange] = []
            var location = target.location
            let upperBound = min(NSMaxRange(target), source.length)
            while location < upperBound {
                let range = source.paragraphRange(for: NSRange(location: location, length: 0))
                ranges.append(range)
                let next = NSMaxRange(range)
                guard next > location else { break }
                location = next
            }
            if ranges.isEmpty, source.length > 0 {
                ranges.append(source.paragraphRange(for: NSRange(location: min(target.location, source.length - 1), length: 0)))
            }
            return ranges
        }

        private func continueListIfNeeded(in textView: NSTextView) -> Bool {
            let source = textView.string as NSString
            let selection = textView.selectedRange()
            guard selection.length == 0, selection.location <= source.length else { return false }
            let probe = max(0, min(selection.location, source.length) - 1)
            let lineRange = source.lineRange(for: NSRange(location: probe, length: 0))
            let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let prefixes = ["• ", "☐ ", "☑ "]
            var nextPrefix = prefixes.first(where: line.hasPrefix)
            if nextPrefix == nil,
               let match = try? NSRegularExpression(pattern: #"^(\d+)\.\s"#).firstMatch(
                   in: line,
                   range: NSRange(location: 0, length: (line as NSString).length)
               ),
               let numberRange = Range(match.range(at: 1), in: line),
               let number = Int(line[numberRange]) {
                nextPrefix = "\(number + 1). "
            }
            guard let nextPrefix else { return false }
            let currentPrefixLength: Int
            if line.first?.isNumber == true,
               let dot = line.firstIndex(of: ".") {
                currentPrefixLength = line.distance(from: line.startIndex, to: line.index(after: dot)) + 1
            } else {
                currentPrefixLength = 2
            }
            let content = String(line.dropFirst(min(currentPrefixLength, line.count))).trimmingCharacters(in: .whitespaces)
            if content.isEmpty {
                let deleteRange = NSRange(location: lineRange.location, length: min(currentPrefixLength, source.length - lineRange.location))
                textView.textStorage?.replaceCharacters(in: deleteRange, with: "")
                textView.insertNewline(nil)
            } else {
                textView.insertText("\n\(nextPrefix)", replacementRange: selection)
            }
            textView.didChangeText()
            return true
        }
    }
}

private final class RichNoteTextView: NSTextView {
    var onCheckboxClick: ((Int) -> Void)?

    override func paste(_ sender: Any?) {
        let replacement = selectedRange()
        let previousLength = textStorage?.length ?? 0
        super.paste(sender)
        guard let textStorage else { return }
        let insertedLength = textStorage.length - (previousLength - replacement.length)
        guard insertedLength > 0, replacement.location <= textStorage.length else {
            ensureReadableTypingColor()
            return
        }
        let safeLength = min(insertedLength, textStorage.length - replacement.location)
        let insertedRange = NSRange(location: replacement.location, length: safeLength)
        let normalized = NoteContent.normalizedPastedContent(
            textStorage.attributedSubstring(from: insertedRange)
        )
        textStorage.replaceCharacters(in: insertedRange, with: normalized)
        setSelectedRange(NSRange(location: NSMaxRange(insertedRange), length: 0))
        ensureReadableTypingColor()
    }

    private func ensureReadableTypingColor() {
        var attributes = typingAttributes
        attributes[.foregroundColor] = NSColor.white.withAlphaComponent(0.88)
        attributes.removeValue(forKey: .backgroundColor)
        typingAttributes = attributes
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let layoutManager,
              let textContainer
        else {
            super.mouseDown(with: event)
            return
        }
        let containerPoint = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        let source = string as NSString
        if characterIndex < source.length {
            let value = source.substring(with: NSRange(location: characterIndex, length: 1))
            if value == "☐" || value == "☑" {
                onCheckboxClick?(characterIndex)
                return
            }
        }
        super.mouseDown(with: event)
    }
}

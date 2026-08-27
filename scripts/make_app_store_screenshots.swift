import AppKit

private let canvasSize = NSSize(width: 2880, height: 1800)
private let project = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
private let source = project.appendingPathComponent("AppStore/screenshots/source", isDirectory: true)
private let output = project.appendingPathComponent("AppStore/screenshots/final", isDirectory: true)

private struct Shot {
    let filename: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let image: String
    let imageWidth: CGFloat
    let imageY: CGFloat
    let accent: NSColor
}

private let shots: [Shot] = [
    Shot(
        filename: "01-task-status.png",
        eyebrow: "后台工作状态中枢",
        title: "后台任务，抬眼就知道",
        subtitle: "运行、完成与中断状态，持续显示在屏幕顶部",
        image: "dashboard-demo.png",
        imageWidth: 930,
        imageY: 92,
        accent: NSColor(calibratedRed: 0.20, green: 0.86, blue: 0.52, alpha: 1)
    ),
    Shot(
        filename: "02-official-usage.png",
        eyebrow: "官方周用量 · 本机同步",
        title: "用量变化，不必反复切换窗口",
        subtitle: "读取用户授权的本机 Codex 事件，不估算、不上传",
        image: "dashboard-demo.png",
        imageWidth: 930,
        imageY: -160,
        accent: NSColor(calibratedRed: 0.18, green: 0.57, blue: 1.00, alpha: 1)
    ),
    Shot(
        filename: "03-customize.png",
        eyebrow: "布局与模块",
        title: "按你的工作方式排列",
        subtitle: "自由选择状态模块、布局密度与显示顺序",
        image: "settings-demo.png",
        imageWidth: 1040,
        imageY: 92,
        accent: NSColor(calibratedRed: 0.30, green: 0.67, blue: 1.00, alpha: 1)
    )
]

private func drawText(_ string: String, rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    string.draw(in: rect, withAttributes: [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ])
}

private func makeShot(_ shot: Shot) throws {
    guard let image = NSImage(contentsOf: source.appendingPathComponent(shot.image)) else {
        throw NSError(domain: "Screenshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing \(shot.image)"])
    }

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "Screenshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create canvas"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }

    let bounds = NSRect(origin: .zero, size: canvasSize)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.035, green: 0.050, blue: 0.075, alpha: 1),
        NSColor(calibratedRed: 0.075, green: 0.105, blue: 0.155, alpha: 1),
        NSColor(calibratedRed: 0.025, green: 0.035, blue: 0.055, alpha: 1)
    ])!
    gradient.draw(in: bounds, angle: -18)

    let glowRect = NSRect(x: 280, y: 80, width: 2320, height: 1120)
    let glow = NSGradient(starting: shot.accent.withAlphaComponent(0.18), ending: shot.accent.withAlphaComponent(0))!
    glow.draw(in: NSBezierPath(ovalIn: glowRect), relativeCenterPosition: .zero)

    let eyebrowRect = NSRect(x: 240, y: 1540, width: 2400, height: 62)
    drawText(shot.eyebrow, rect: eyebrowRect, font: .systemFont(ofSize: 38, weight: .semibold), color: shot.accent)
    let titleRect = NSRect(x: 180, y: 1370, width: 2520, height: 136)
    drawText(shot.title, rect: titleRect, font: .systemFont(ofSize: 88, weight: .bold), color: .white)
    let subtitleRect = NSRect(x: 240, y: 1270, width: 2400, height: 72)
    drawText(shot.subtitle, rect: subtitleRect, font: .systemFont(ofSize: 40, weight: .regular), color: NSColor.white.withAlphaComponent(0.68))

    let scale = shot.imageWidth / image.size.width
    let imageHeight = image.size.height * scale
    let imageRect = NSRect(x: (canvasSize.width - shot.imageWidth) / 2, y: shot.imageY, width: shot.imageWidth, height: imageHeight)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.72)
    shadow.shadowBlurRadius = 65
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.withAlphaComponent(0.01).setFill()
    NSBezierPath(roundedRect: imageRect.insetBy(dx: -2, dy: -2), xRadius: 60, yRadius: 60).fill()
    NSGraphicsContext.restoreGraphicsState()
    image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

    context.flushGraphics()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Screenshot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode \(shot.filename)"])
    }
    try png.write(to: output.appendingPathComponent(shot.filename), options: .atomic)
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for shot in shots {
    try makeShot(shot)
    print("Created \(shot.filename)")
}

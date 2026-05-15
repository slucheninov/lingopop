#!/usr/bin/env swift
// Generates stylized mockup PNGs for the public README:
//   • popup.png  — translation popup over a soft desktop background
//   • menu.png   — menu-bar status dropdown
//
// Usage: swift scripts/generate-mockups.swift <output-dir>

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default
if !fm.fileExists(atPath: outDir) {
    try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
}

// ── Shared helpers ────────────────────────────────────────────────────────

extension NSBezierPath {
    var cgPathFromCGPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

func savePNG(_ image: NSImage, to path: String) throws {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw NSError(domain: "mockup", code: 1, userInfo: [NSLocalizedDescriptionKey: "no CGImage"])
    }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "mockup", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try data.write(to: URL(fileURLWithPath: path))
}

func drawDesktop(in rect: NSRect) {
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.18, green: 0.22, blue: 0.34, alpha: 1.0),
        NSColor(srgbRed: 0.36, green: 0.28, blue: 0.52, alpha: 1.0),
        NSColor(srgbRed: 0.55, green: 0.30, blue: 0.62, alpha: 1.0)
    ], atLocations: [0.0, 0.6, 1.0], colorSpace: .sRGB)!
    gradient.draw(in: rect, angle: -65)
    // soft blurry blobs
    for blob in [(rect.midX - 280, rect.midY + 140, 320.0),
                 (rect.midX + 220, rect.midY - 100, 260.0)] {
        let radius = CGFloat(blob.2)
        let center = NSPoint(x: blob.0, y: blob.1)
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius*2, height: radius*2))
        NSColor.white.withAlphaComponent(0.06).setFill()
        circle.fill()
    }
}

func drawShadow(for path: NSBezierPath, offset: NSSize, blur: CGFloat, alpha: CGFloat) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setShadow(offset: offset, blur: blur, color: NSColor.black.withAlphaComponent(alpha).cgColor)
    NSColor.white.setFill()
    path.fill()
    ctx.restoreGState()
}

func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color
    ]
    text.draw(at: point, withAttributes: attrs)
}

func textSize(_ text: String, font: NSFont) -> NSSize {
    NSAttributedString(string: text, attributes: [.font: font]).size()
}

func drawBadge(_ text: String, at origin: NSPoint, font: NSFont, fill: NSColor, fg: NSColor) -> NSRect {
    let size = textSize(text, font: font)
    let padding = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    let rect = NSRect(
        x: origin.x,
        y: origin.y,
        width: size.width + padding.left + padding.right,
        height: size.height + padding.top + padding.bottom
    )
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
    fill.setFill()
    path.fill()
    drawText(text, at: NSPoint(x: rect.minX + padding.left, y: rect.minY + padding.bottom), font: font, color: fg)
    return rect
}

// ── Popup mockup ──────────────────────────────────────────────────────────

let popupCanvas = NSSize(width: 1200, height: 720)
let popupImage = NSImage(size: popupCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    // popup card
    let cardWidth: CGFloat = 560
    let cardHeight: CGFloat = 220
    let cardOrigin = NSPoint(x: (rect.width - cardWidth) / 2, y: (rect.height - cardHeight) / 2 - 20)
    let cardRect = NSRect(origin: cardOrigin, size: NSSize(width: cardWidth, height: cardHeight))
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 18, yRadius: 18)

    drawShadow(for: cardPath, offset: NSSize(width: 0, height: -24), blur: 40, alpha: 0.45)

    // material fill — slightly translucent white with subtle gradient
    NSGraphicsContext.current!.cgContext.saveGState()
    cardPath.addClip()
    let cardGradient = NSGradient(colors: [
        NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96),
        NSColor(srgbRed: 0.97, green: 0.97, blue: 0.99, alpha: 0.96)
    ])!
    cardGradient.draw(in: cardRect, angle: -90)
    NSGraphicsContext.current!.cgContext.restoreGState()

    // header row
    let headerY = cardRect.maxY - 38
    let badgeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    let providerBadge = drawBadge(
        "🌐  Claude → Ukrainian",
        at: NSPoint(x: cardRect.minX + 18, y: headerY),
        font: badgeFont,
        fill: NSColor(srgbRed: 0.93, green: 0.93, blue: 0.97, alpha: 1.0),
        fg: NSColor(srgbRed: 0.20, green: 0.18, blue: 0.40, alpha: 1.0)
    )

    // copy & replace buttons mock
    let buttonFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    let buttonFg = NSColor(srgbRed: 0.35, green: 0.35, blue: 0.45, alpha: 1.0)
    var bx = cardRect.maxX - 18 - textSize("Replace", font: buttonFont).width - 18
    drawText("📋  Copy", at: NSPoint(x: bx - 80, y: headerY + 5), font: buttonFont, color: buttonFg)
    drawText("⤺  Replace", at: NSPoint(x: bx, y: headerY + 5), font: buttonFont, color: buttonFg)

    _ = providerBadge // silence unused warning

    // translated text
    let translatedFont = NSFont.systemFont(ofSize: 22, weight: .regular)
    let translatedText = "Привіт! Радий тебе бачити сьогодні."
    let translatedColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)
    drawText(translatedText, at: NSPoint(x: cardRect.minX + 22, y: cardRect.minY + 78), font: translatedFont, color: translatedColor)

    // original (smaller, gray) preview
    let origFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    let origText = "Original: Hi! Glad to see you today."
    drawText(origText, at: NSPoint(x: cardRect.minX + 22, y: cardRect.minY + 28), font: origFont, color: NSColor(white: 0.5, alpha: 1.0))

    // small caption below the card
    let caption = NSAttributedString(string: "Translate · Fix grammar · Rewrite — wherever your cursor is.", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85)
    ])
    let capSize = caption.size()
    caption.draw(at: NSPoint(x: (rect.width - capSize.width) / 2, y: cardRect.minY - 56))

    return true
}
try savePNG(popupImage, to: "\(outDir)/popup.png")
print("Wrote \(outDir)/popup.png")

// ── Menu mockup ───────────────────────────────────────────────────────────

let menuCanvas = NSSize(width: 1200, height: 720)
let menuImage = NSImage(size: menuCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    // fake menu bar across the top
    let barRect = NSRect(x: 0, y: rect.height - 28, width: rect.width, height: 28)
    NSColor.black.withAlphaComponent(0.45).setFill()
    NSBezierPath(rect: barRect).fill()

    // status icons row (right-aligned)
    let iconY = barRect.minY + 6
    var iconX = rect.width - 18
    let iconFont = NSFont.systemFont(ofSize: 12)
    for icon in ["􀊥", "􀛨", "􀎰", "􀋲", "13:42"].reversed() {
        let w = textSize(icon, font: iconFont).width
        iconX -= w + 14
        drawText(icon, at: NSPoint(x: iconX, y: iconY), font: iconFont, color: NSColor.white.withAlphaComponent(0.85))
    }

    // LingoPop icon position in the bar
    let lingoIconRect = NSRect(x: rect.width - 270, y: barRect.minY + 4, width: 20, height: 20)
    let lingoBg = NSBezierPath(roundedRect: lingoIconRect, xRadius: 5, yRadius: 5)
    NSColor(srgbRed: 0.42, green: 0.20, blue: 0.95, alpha: 1.0).setFill()
    lingoBg.fill()
    drawText("A文", at: NSPoint(x: lingoIconRect.minX + 2, y: lingoIconRect.minY + 1),
             font: NSFont.systemFont(ofSize: 9, weight: .bold), color: .white)

    // dropdown card under the icon
    let menuW: CGFloat = 280
    let menuH: CGFloat = 320
    let menuOrigin = NSPoint(x: lingoIconRect.midX - menuW / 2 + 80, y: barRect.minY - menuH - 8)
    let menuRect = NSRect(origin: menuOrigin, size: NSSize(width: menuW, height: menuH))
    let menuPath = NSBezierPath(roundedRect: menuRect, xRadius: 10, yRadius: 10)

    drawShadow(for: menuPath, offset: NSSize(width: 0, height: -16), blur: 32, alpha: 0.50)

    NSGraphicsContext.current!.cgContext.saveGState()
    menuPath.addClip()
    NSColor(srgbRed: 0.96, green: 0.96, blue: 0.98, alpha: 0.98).setFill()
    menuPath.fill()
    NSGraphicsContext.current!.cgContext.restoreGState()

    // menu items
    struct Item { let icon: String; let title: String; let shortcut: String; let separator: Bool }
    let items: [Item] = [
        .init(icon: "✓", title: "Accessibility: granted", shortcut: "", separator: true),
        .init(icon: "🌐", title: "Translate", shortcut: "⌥T", separator: false),
        .init(icon: "✓", title: "Fix grammar", shortcut: "⌥G", separator: false),
        .init(icon: "✨", title: "Rewrite", shortcut: "⌥R", separator: true),
        .init(icon: "🎯", title: "Target: Ukrainian", shortcut: "▸", separator: false),
        .init(icon: "📜", title: "History…", shortcut: "", separator: false),
        .init(icon: "⚙︎", title: "Settings…", shortcut: "⌘,", separator: true),
        .init(icon: "⏻", title: "Quit LingoPop", shortcut: "⌘Q", separator: false)
    ]
    let titleFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    let shortcutFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    let titleColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.18, alpha: 1.0)
    let shortcutColor = NSColor(white: 0.5, alpha: 1.0)
    let iconColor = NSColor(srgbRed: 0.40, green: 0.20, blue: 0.85, alpha: 0.9)

    var y = menuRect.maxY - 24
    for item in items {
        drawText(item.icon, at: NSPoint(x: menuRect.minX + 16, y: y), font: titleFont, color: iconColor)
        drawText(item.title, at: NSPoint(x: menuRect.minX + 44, y: y), font: titleFont, color: titleColor)
        if !item.shortcut.isEmpty {
            let scSize = textSize(item.shortcut, font: shortcutFont)
            drawText(item.shortcut, at: NSPoint(x: menuRect.maxX - 16 - scSize.width, y: y + 1), font: shortcutFont, color: shortcutColor)
        }
        y -= 28
        if item.separator {
            let sepY = y + 14
            let sep = NSBezierPath()
            sep.move(to: NSPoint(x: menuRect.minX + 12, y: sepY))
            sep.line(to: NSPoint(x: menuRect.maxX - 12, y: sepY))
            NSColor(white: 0, alpha: 0.10).setStroke()
            sep.lineWidth = 0.5
            sep.stroke()
            y -= 4
        }
    }

    // bottom caption
    let cap = NSAttributedString(string: "Five providers · per-provider fallback · iCloud-synced settings",
                                  attributes: [
                                    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                                    .foregroundColor: NSColor.white.withAlphaComponent(0.85)
                                  ])
    let cs = cap.size()
    cap.draw(at: NSPoint(x: (rect.width - cs.width) / 2, y: 60))

    return true
}
try savePNG(menuImage, to: "\(outDir)/menu.png")
print("Wrote \(outDir)/menu.png")

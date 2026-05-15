#!/usr/bin/env swift
// Generates stylized mockup PNGs for the public README:
//   • popup.png  — compact translation popup over a soft desktop background
//   • menu.png   — menu-bar status dropdown
//
// Mockups intentionally match the real PopupView/menu layout closely so a
// new user sees what they'll actually get.
//
// Usage: swift scripts/generate-mockups.swift <output-dir>

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default
if !fm.fileExists(atPath: outDir) {
    try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
}

// ── Shared helpers ────────────────────────────────────────────────────────

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
    for blob in [(rect.midX - 280, rect.midY + 140, 320.0),
                 (rect.midX + 220, rect.midY - 100, 260.0)] {
        let radius = CGFloat(blob.2)
        let center = NSPoint(x: blob.0, y: blob.1)
        let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius*2, height: radius*2))
        NSColor.white.withAlphaComponent(0.06).setFill()
        circle.fill()
    }
}

func drawShadow(for path: NSBezierPath, offset: NSSize, blur: CGFloat, alpha: CGFloat, fill: NSColor) {
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.setShadow(offset: offset, blur: blur, color: NSColor.black.withAlphaComponent(alpha).cgColor)
    fill.setFill()
    path.fill()
    ctx.restoreGState()
}

func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    text.draw(at: point, withAttributes: attrs)
}

func textSize(_ text: String, font: NSFont) -> NSSize {
    NSAttributedString(string: text, attributes: [.font: font]).size()
}

// Draws a tinted SF Symbol at the given point. Returns the advance width.
@discardableResult
func drawSymbol(_ name: String, at point: NSPoint, fontSize: CGFloat, color: NSColor) -> CGFloat {
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return 0 }
    let sizeConfig = NSImage.SymbolConfiguration(pointSize: fontSize, weight: .regular)
    let paletteConfig = NSImage.SymbolConfiguration(paletteColors: [color])
    let combined = sizeConfig.applying(paletteConfig)
    let configured = image.withSymbolConfiguration(combined) ?? image
    let size = configured.size
    let rect = NSRect(x: point.x, y: point.y, width: size.width, height: size.height)
    configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    return size.width
}

// ── Popup mockup ──────────────────────────────────────────────────────────
// Matches the real PopupView: ~360pt wide card, regularMaterial background,
// rounded 12, single line: globe icon → "Claude → Ukrainian", Copy, Replace, retry.

let popupCanvas = NSSize(width: 1200, height: 720)
let popupImage = NSImage(size: popupCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    // Scale the popup 2x for visibility on the larger canvas
    let scale: CGFloat = 2.0
    let popupW: CGFloat = 360 * scale
    let popupH: CGFloat = 96 * scale
    let popupOrigin = NSPoint(x: (rect.width - popupW) / 2, y: (rect.height - popupH) / 2)
    let popupRect = NSRect(origin: popupOrigin, size: NSSize(width: popupW, height: popupH))
    let popupPath = NSBezierPath(roundedRect: popupRect, xRadius: 12 * scale, yRadius: 12 * scale)

    // Shadow + material-like fill
    drawShadow(for: popupPath, offset: NSSize(width: 0, height: -10 * scale), blur: 28 * scale, alpha: 0.32, fill: NSColor.white)

    NSGraphicsContext.current!.cgContext.saveGState()
    popupPath.addClip()
    let materialGrad = NSGradient(colors: [
        NSColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 0.96),
        NSColor(srgbRed: 0.91, green: 0.91, blue: 0.94, alpha: 0.96)
    ])!
    materialGrad.draw(in: popupRect, angle: -90)

    // Subtle hairline border
    NSColor.black.withAlphaComponent(0.06).setStroke()
    let border = NSBezierPath(roundedRect: popupRect, xRadius: 12 * scale, yRadius: 12 * scale)
    border.lineWidth = 0.5 * scale
    border.stroke()
    NSGraphicsContext.current!.cgContext.restoreGState()

    // Layout inside the popup
    let pad: CGFloat = 14 * scale
    let secondaryColor = NSColor(srgbRed: 0.36, green: 0.36, blue: 0.40, alpha: 1.0)
    let primaryColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)

    // Top row
    let topY = popupRect.maxY - pad - 12 * scale
    let smallFont = NSFont.systemFont(ofSize: 10 * scale, weight: .semibold)
    let mediumFont = NSFont.systemFont(ofSize: 10 * scale, weight: .medium)

    // globe icon + "Claude → Ukrainian"
    var x = popupRect.minX + pad
    let symW = drawSymbol("globe", at: NSPoint(x: x, y: topY - 2 * scale), fontSize: 12 * scale, color: secondaryColor)
    x += symW + 5 * scale
    drawText("Claude → Ukrainian", at: NSPoint(x: x, y: topY), font: smallFont, color: secondaryColor)

    // Right-aligned buttons: 🔄 retry, Replace, Copy (rendered right-to-left)
    var rx = popupRect.maxX - pad
    // retry icon
    let retryW = drawSymbol("arrow.triangle.2.circlepath", at: NSPoint(x: rx - 14 * scale, y: topY - 2 * scale), fontSize: 12 * scale, color: secondaryColor)
    rx -= retryW + 12 * scale
    // Replace label + icon
    let replaceLabel = "Replace"
    let replaceW = textSize(replaceLabel, font: mediumFont).width
    drawText(replaceLabel, at: NSPoint(x: rx - replaceW, y: topY), font: mediumFont, color: secondaryColor)
    rx -= replaceW + 4 * scale
    drawSymbol("arrow.uturn.left", at: NSPoint(x: rx - 12 * scale, y: topY - 2 * scale), fontSize: 11 * scale, color: secondaryColor)
    rx -= 14 * scale + 10 * scale
    // Copy label + icon
    let copyLabel = "Copy"
    let copyW = textSize(copyLabel, font: mediumFont).width
    drawText(copyLabel, at: NSPoint(x: rx - copyW, y: topY), font: mediumFont, color: secondaryColor)
    rx -= copyW + 4 * scale
    drawSymbol("doc.on.doc", at: NSPoint(x: rx - 12 * scale, y: topY - 2 * scale), fontSize: 11 * scale, color: secondaryColor)

    // Translated text
    let bodyFont = NSFont.systemFont(ofSize: 13 * scale, weight: .regular)
    let bodyText = "Висока затримка запит Loki"
    drawText(bodyText, at: NSPoint(x: popupRect.minX + pad, y: popupRect.minY + pad + 6 * scale), font: bodyFont, color: primaryColor)

    // Caption below
    let cap = NSAttributedString(string: "Translate · Fix grammar · Rewrite — wherever your cursor is.", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85)
    ])
    let capSize = cap.size()
    cap.draw(at: NSPoint(x: (rect.width - capSize.width) / 2, y: popupRect.minY - 56))

    return true
}
try savePNG(popupImage, to: "\(outDir)/popup.png")
print("Wrote \(outDir)/popup.png")

// ── Menu mockup ───────────────────────────────────────────────────────────
// Matches the real status-bar dropdown shape & content.

let menuCanvas = NSSize(width: 1200, height: 720)
let menuImage = NSImage(size: menuCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 1.6
    let menuW: CGFloat = 280 * scale
    let rowH: CGFloat = 26 * scale

    // ── Row data
    enum Row {
        case header(String)
        case operation(symbol: String, title: String, hotkey: String)
        case submenu(title: String)
        case command(title: String, key: String)
        case separator
    }
    let rows: [Row] = [
        .header("Accessibility: granted ✓"),
        .separator,
        .operation(symbol: "globe", title: "Translate", hotkey: "⌥T"),
        .operation(symbol: "checkmark.seal", title: "Fix grammar", hotkey: "⌥G"),
        .operation(symbol: "wand.and.stars", title: "Rewrite", hotkey: "⌥R"),
        .submenu(title: "Target: Ukrainian"),
        .command(title: "History…", key: "⌘H"),
        .command(title: "Settings…", key: "⌘,"),
        .separator,
        .command(title: "Quit LingoPop", key: "⌘Q")
    ]

    // total height
    var contentHeight: CGFloat = 8 * scale
    for r in rows {
        switch r {
        case .separator: contentHeight += 9 * scale
        default: contentHeight += rowH
        }
    }
    contentHeight += 8 * scale

    let menuRect = NSRect(
        x: (rect.width - menuW) / 2,
        y: (rect.height - contentHeight) / 2,
        width: menuW,
        height: contentHeight
    )
    let menuPath = NSBezierPath(roundedRect: menuRect, xRadius: 10 * scale, yRadius: 10 * scale)
    drawShadow(for: menuPath, offset: NSSize(width: 0, height: -18 * scale), blur: 36 * scale, alpha: 0.45, fill: NSColor.white)

    // material fill (slightly darker than popup, like macOS Sonoma dark glass on light)
    NSGraphicsContext.current!.cgContext.saveGState()
    menuPath.addClip()
    let materialGrad = NSGradient(colors: [
        NSColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 0.98),
        NSColor(srgbRed: 0.91, green: 0.91, blue: 0.94, alpha: 0.98)
    ])!
    materialGrad.draw(in: menuRect, angle: -90)
    NSColor.black.withAlphaComponent(0.06).setStroke()
    let border = NSBezierPath(roundedRect: menuRect, xRadius: 10 * scale, yRadius: 10 * scale)
    border.lineWidth = 0.5 * scale
    border.stroke()
    NSGraphicsContext.current!.cgContext.restoreGState()

    // colors
    let primary = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let secondary = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0)
    let disabled = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.60, alpha: 1.0)

    let titleFont = NSFont.systemFont(ofSize: 13 * scale, weight: .regular)
    let shortcutFont = NSFont.systemFont(ofSize: 12 * scale, weight: .regular)

    // draw rows top-down
    var y = menuRect.maxY - 8 * scale
    for r in rows {
        switch r {
        case .header(let text):
            y -= rowH
            drawText(text, at: NSPoint(x: menuRect.minX + 24 * scale, y: y + 4 * scale), font: titleFont, color: disabled)
        case .operation(let symbol, let title, let hotkey):
            y -= rowH
            drawSymbol(symbol, at: NSPoint(x: menuRect.minX + 14 * scale, y: y + 3 * scale), fontSize: 13 * scale, color: primary)
            drawText("\(title) (\(hotkey))", at: NSPoint(x: menuRect.minX + 40 * scale, y: y + 4 * scale), font: titleFont, color: primary)
        case .submenu(let title):
            y -= rowH
            drawText(title, at: NSPoint(x: menuRect.minX + 24 * scale, y: y + 4 * scale), font: titleFont, color: primary)
            // chevron right
            drawSymbol("chevron.right", at: NSPoint(x: menuRect.maxX - 22 * scale, y: y + 3 * scale), fontSize: 11 * scale, color: secondary)
        case .command(let title, let key):
            y -= rowH
            drawText(title, at: NSPoint(x: menuRect.minX + 24 * scale, y: y + 4 * scale), font: titleFont, color: primary)
            let scSize = textSize(key, font: shortcutFont)
            drawText(key, at: NSPoint(x: menuRect.maxX - 18 * scale - scSize.width, y: y + 5 * scale), font: shortcutFont, color: secondary)
        case .separator:
            y -= 9 * scale
            let sepY = y + 5 * scale
            let sep = NSBezierPath()
            sep.move(to: NSPoint(x: menuRect.minX + 10 * scale, y: sepY))
            sep.line(to: NSPoint(x: menuRect.maxX - 10 * scale, y: sepY))
            NSColor.black.withAlphaComponent(0.10).setStroke()
            sep.lineWidth = 0.5 * scale
            sep.stroke()
        }
    }

    // bottom caption
    let cap = NSAttributedString(string: "Three operations · five providers · iCloud-synced settings",
                                  attributes: [
                                    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                                    .foregroundColor: NSColor.white.withAlphaComponent(0.85)
                                  ])
    let cs = cap.size()
    cap.draw(at: NSPoint(x: (rect.width - cs.width) / 2, y: menuRect.minY - 56))

    return true
}
try savePNG(menuImage, to: "\(outDir)/menu.png")
print("Wrote \(outDir)/menu.png")

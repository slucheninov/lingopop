// DEPRECATED — Use scripts/render-screenshots.swift (see generate-screenshots.sh).
// This hand-drawn fallback is kept for reference only.
#!/usr/bin/env swift
// DEPRECATED — use scripts/render-screenshots.swift (native SwiftUI/AppKit rendering).
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

// ── App fixture / canonical defaults ────────────────────────────────────────
struct AppFixture {
    static let version         = "0.3.2"
    static let targetLanguage  = "Ukrainian"
    static let activeProvider  = "Claude"
    static let claudeModel     = "claude-haiku-4-5"
    static let claudeBaseURL   = "https://api.anthropic.com"
    static let maxInputChars   = "5000"
    static let historySize     = "10"
    static let popupFontSize   = "13 pt"
    static let settingsTabs    = ["Main", "Providers", "Shortcuts", "Usage", "About"]
    // selectedTab indices
    static let tabMain         = 0
    static let tabProviders    = 1
    static let tabShortcuts    = 2
    static let tabAbout        = 4
    // Fixture text
    static let fixtureTranslated = "Дякую за швидку відповідь, передам команді."
    static let fixtureOCRText    = "Bonjour, comment allez-vous aujourd'hui?"
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

let popupCanvas = NSSize(width: 1200, height: 720)
let popupImage = NSImage(size: popupCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 2.0
    let popupW: CGFloat = 360 * scale
    let popupH: CGFloat = 150 * scale
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

    let secondaryColor = NSColor(srgbRed: 0.36, green: 0.36, blue: 0.40, alpha: 1.0)
    let primaryColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let smallFont = NSFont.systemFont(ofSize: 10 * scale, weight: .semibold)

    // Drag handle
    let handleW: CGFloat = 28 * scale
    let handleH: CGFloat = 3 * scale
    let handleX = popupRect.midX - handleW / 2
    let handleY = popupRect.maxY - 8 * scale
    let handleRect = NSRect(x: handleX, y: handleY, width: handleW, height: handleH)
    let handlePath = NSBezierPath(roundedRect: handleRect, xRadius: handleH / 2, yRadius: handleH / 2)
    NSColor.black.withAlphaComponent(0.15).setFill()
    handlePath.fill()

    // Header row
    let topY = popupRect.maxY - 20 * scale - 10 * scale
    var x = popupRect.minX + 14 * scale
    let symW = drawSymbol("globe", at: NSPoint(x: x, y: topY - 2 * scale), fontSize: 12 * scale, color: secondaryColor)
    x += symW + 5 * scale
    let providerLabel = "Claude →"
    drawText(providerLabel, at: NSPoint(x: x, y: topY), font: smallFont, color: secondaryColor)
    x += textSize(providerLabel, font: smallFont).width + 5 * scale
    let langLabel = "Ukrainian"
    drawText(langLabel, at: NSPoint(x: x, y: topY), font: smallFont, color: primaryColor)
    x += textSize(langLabel, font: smallFont).width + 4 * scale
    drawSymbol("chevron.down", at: NSPoint(x: x, y: topY - 1 * scale), fontSize: 9 * scale, color: secondaryColor)

    // Body text
    let bodyFont = NSFont.systemFont(ofSize: 13 * scale, weight: .regular)
    let bodyY = popupRect.minY + 46 * scale
    drawText(AppFixture.fixtureTranslated, at: NSPoint(x: popupRect.minX + 14 * scale, y: bodyY), font: bodyFont, color: primaryColor)

    // Button row — 6 small bordered pill buttons
    let btnH: CGFloat = 22 * scale
    let btnY = popupRect.minY + 12 * scale
    let pillFont = NSFont.systemFont(ofSize: 9 * scale, weight: .medium)
    let pillBg = NSColor.white.withAlphaComponent(0.75)

    func drawPillButton(icon: String, label: String, atX bx: CGFloat) -> CGFloat {
        let iconW = drawSymbol(icon, at: NSPoint(x: bx + 5 * scale, y: btnY + (btnH - 11 * scale) / 2), fontSize: 10 * scale, color: secondaryColor)
        let lts = textSize(label, font: pillFont)
        let pillW = 5 * scale + iconW + 3 * scale + lts.width + 7 * scale
        let pillRect = NSRect(x: bx, y: btnY, width: pillW, height: btnH)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: btnH / 2, yRadius: btnH / 2)
        pillBg.setFill()
        pillPath.fill()
        NSColor.black.withAlphaComponent(0.06).setStroke()
        pillPath.lineWidth = 0.5 * scale
        pillPath.stroke()
        drawSymbol(icon, at: NSPoint(x: bx + 5 * scale, y: btnY + (btnH - 11 * scale) / 2), fontSize: 10 * scale, color: secondaryColor)
        drawText(label, at: NSPoint(x: bx + 5 * scale + iconW + 3 * scale, y: btnY + (btnH - lts.height) / 2), font: pillFont, color: secondaryColor)
        return pillW
    }

    var bx = popupRect.minX + 14 * scale
    let gap: CGFloat = 5 * scale
    bx += drawPillButton(icon: "doc.on.doc", label: "Copy", atX: bx) + gap
    bx += drawPillButton(icon: "arrow.uturn.left", label: "Replace", atX: bx) + gap
    bx += drawPillButton(icon: "wand.and.stars", label: "Rewrite", atX: bx) + gap
    bx += drawPillButton(icon: "text.magnifyingglass", label: "Explain", atX: bx) + gap

    // Retry pill right-aligned
    let retryFont = NSFont.systemFont(ofSize: 9 * scale, weight: .medium)
    let retryLabel = "Retry ▾"
    let retryIconW: CGFloat = 11 * scale
    let retryLabelW = textSize(retryLabel, font: retryFont).width
    let retryPillW = 5 * scale + retryIconW + 3 * scale + retryLabelW + 7 * scale
    let retryX = popupRect.maxX - 14 * scale - retryPillW
    let retryPillRect = NSRect(x: retryX, y: btnY, width: retryPillW, height: btnH)
    let retryPillPath = NSBezierPath(roundedRect: retryPillRect, xRadius: btnH / 2, yRadius: btnH / 2)
    pillBg.setFill()
    retryPillPath.fill()
    NSColor.black.withAlphaComponent(0.06).setStroke()
    retryPillPath.lineWidth = 0.5 * scale
    retryPillPath.stroke()
    drawSymbol("arrow.triangle.2.circlepath", at: NSPoint(x: retryX + 5 * scale, y: btnY + (btnH - 11 * scale) / 2), fontSize: 10 * scale, color: secondaryColor)
    drawText(retryLabel, at: NSPoint(x: retryX + 5 * scale + retryIconW + 3 * scale, y: btnY + (btnH - textSize(retryLabel, font: retryFont).height) / 2), font: retryFont, color: secondaryColor)

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

let menuCanvas = NSSize(width: 1200, height: 720)
let menuImage = NSImage(size: menuCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 1.6
    let menuW: CGFloat = 280 * scale

    // ── Row data
    enum Row {
        case header(String)
        case recent(original: String, translated: String, shortcut: String)
        case operation(symbol: String, title: String, hotkey: String?)
        case submenu(title: String)
        case command(title: String, key: String)
        case separator
    }
    let rows: [Row] = [
        .header("Select the clip you want to add to your clipboard"),
        .recent(original: "Thanks for the quick reply, I'll pass it to the team.",
                translated: "Дякую за швидку відповідь, передам команді.",
                shortcut: "⌘1"),
        .recent(original: "the app works great and is very usefull",
                translated: "The app works great and is very useful",
                shortcut: "⌘2"),
        .recent(original: "Bonjour, comment allez-vous aujourd'hui?",
                translated: "Hello, how are you today?",
                shortcut: "⌘3"),
        .separator,
        .operation(symbol: "globe",             title: "Translate",        hotkey: "⌥T"),
        .operation(symbol: "checkmark.seal",    title: "Fix grammar",      hotkey: nil),
        .operation(symbol: "wand.and.stars",    title: "Rewrite",          hotkey: nil),
        .operation(symbol: "text.magnifyingglass", title: "Explain",       hotkey: nil),
        .operation(symbol: "camera.viewfinder", title: "Screen Translate", hotkey: nil),
        .separator,
        .submenu(title: "Target: Ukrainian"),
        .command(title: "History…",      key: "⌘H"),
        .command(title: "Settings…",     key: "⌘,"),
        .separator,
        .command(title: "Quit LingoPop", key: "⌘Q")
    ]

    // total height
    var contentHeight: CGFloat = 8 * scale
    for r in rows {
        switch r {
        case .separator: contentHeight += 9 * scale
        case .header: contentHeight += 28 * scale
        default: contentHeight += 26 * scale
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

    let primary = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let secondary = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0)

    let titleFont = NSFont.systemFont(ofSize: 13 * scale, weight: .regular)
    let shortcutFont = NSFont.systemFont(ofSize: 12 * scale, weight: .regular)
    let headerFont = NSFont.systemFont(ofSize: 10 * scale, weight: .regular)
    let recentFont = NSFont.systemFont(ofSize: 11 * scale, weight: .regular)

    var y = menuRect.maxY - 8 * scale
    for r in rows {
        switch r {
        case .header(let text):
            let rowH: CGFloat = 28 * scale
            y -= rowH
            drawText(text, at: NSPoint(x: menuRect.minX + 14 * scale, y: y + (rowH - textSize(text, font: headerFont).height) / 2), font: headerFont, color: secondary)
        case .recent(let original, let translated, let shortcut):
            let rowH: CGFloat = 26 * scale
            y -= rowH
            let combined = original + " → " + translated
            let displayText = combined.count > 55 ? String(combined.prefix(55)) + "…" : combined
            drawText(displayText, at: NSPoint(x: menuRect.minX + 14 * scale, y: y + (rowH - textSize(displayText, font: recentFont).height) / 2), font: recentFont, color: primary)
            let scSize = textSize(shortcut, font: shortcutFont)
            drawText(shortcut, at: NSPoint(x: menuRect.maxX - 14 * scale - scSize.width, y: y + (rowH - scSize.height) / 2), font: shortcutFont, color: secondary)
        case .operation(let symbol, let title, let hotkey):
            let rowH: CGFloat = 26 * scale
            y -= rowH
            drawSymbol(symbol, at: NSPoint(x: menuRect.minX + 14 * scale, y: y + (rowH - 13 * scale) / 2), fontSize: 13 * scale, color: primary)
            drawText(title, at: NSPoint(x: menuRect.minX + 36 * scale, y: y + (rowH - textSize(title, font: titleFont).height) / 2), font: titleFont, color: primary)
            if let hotkey = hotkey {
                let scSize = textSize(hotkey, font: shortcutFont)
                drawText(hotkey, at: NSPoint(x: menuRect.maxX - 18 * scale - scSize.width, y: y + (rowH - scSize.height) / 2), font: shortcutFont, color: secondary)
            }
        case .submenu(let title):
            let rowH: CGFloat = 26 * scale
            y -= rowH
            drawText(title, at: NSPoint(x: menuRect.minX + 24 * scale, y: y + (rowH - textSize(title, font: titleFont).height) / 2), font: titleFont, color: primary)
            drawSymbol("chevron.right", at: NSPoint(x: menuRect.maxX - 22 * scale, y: y + (rowH - 11 * scale) / 2), fontSize: 11 * scale, color: secondary)
        case .command(let title, let key):
            let rowH: CGFloat = 26 * scale
            y -= rowH
            drawText(title, at: NSPoint(x: menuRect.minX + 24 * scale, y: y + (rowH - textSize(title, font: titleFont).height) / 2), font: titleFont, color: primary)
            let scSize = textSize(key, font: shortcutFont)
            drawText(key, at: NSPoint(x: menuRect.maxX - 18 * scale - scSize.width, y: y + (rowH - scSize.height) / 2), font: shortcutFont, color: secondary)
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
    let cap = NSAttributedString(string: "Seven providers · iCloud-synced settings · Screen Translate",
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

// ── Fixture strings — see AppFixture above ────────────────────────────────

// ── Shared window / settings helpers ──────────────────────────────────────

// Draws macOS-style traffic-light buttons (red/yellow/green) at the given origin.
func drawTrafficLights(at origin: NSPoint, scale: CGFloat) {
    let colors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.37, blue: 0.34, alpha: 1.0),  // red
        NSColor(srgbRed: 1.00, green: 0.73, blue: 0.16, alpha: 1.0),  // yellow
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1.0)   // green
    ]
    let r: CGFloat = 6 * scale
    let gap: CGFloat = 8 * scale
    for (i, color) in colors.enumerated() {
        let cx = origin.x + CGFloat(i) * (r * 2 + gap) + r
        let cy = origin.y
        let dot = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        color.setFill()
        dot.fill()
    }
}

// Draws a macOS-style window chrome (title bar + optional tab bar).
// Returns the Y coordinate of the content area top.
func drawWindowChrome(
    in rect: NSRect,
    title: String,
    scale: CGFloat,
    tabs: [String],
    selectedTab: Int
) -> CGFloat {
    let ctx = NSGraphicsContext.current!.cgContext
    let titleBarH: CGFloat = 28 * scale
    let tabBarH: CGFloat = tabs.isEmpty ? 0 : 32 * scale

    // Window background
    let winPath = NSBezierPath(roundedRect: rect, xRadius: 10 * scale, yRadius: 10 * scale)
    drawShadow(for: winPath, offset: NSSize(width: 0, height: -12 * scale), blur: 32 * scale, alpha: 0.38, fill: NSColor.white)

    ctx.saveGState()
    winPath.addClip()

    // Content area (white-ish)
    NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1.0).setFill()
    NSBezierPath(rect: rect).fill()

    // Title bar
    let titleBarRect = NSRect(x: rect.minX, y: rect.maxY - titleBarH, width: rect.width, height: titleBarH)
    let titleBarGrad = NSGradient(colors: [
        NSColor(srgbRed: 0.88, green: 0.88, blue: 0.90, alpha: 1.0),
        NSColor(srgbRed: 0.84, green: 0.84, blue: 0.86, alpha: 1.0)
    ])!
    titleBarGrad.draw(in: titleBarRect, angle: -90)

    // Title text
    let titleFont = NSFont.systemFont(ofSize: 13 * scale, weight: .semibold)
    let titleColor = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
    let ts = textSize(title, font: titleFont)
    drawText(title,
             at: NSPoint(x: rect.midX - ts.width / 2, y: titleBarRect.minY + (titleBarH - ts.height) / 2),
             font: titleFont, color: titleColor)

    // Traffic lights
    drawTrafficLights(at: NSPoint(x: rect.minX + 12 * scale, y: titleBarRect.minY + titleBarH / 2), scale: scale)

    // Separator under title bar
    NSColor.black.withAlphaComponent(0.12).setStroke()
    let sep = NSBezierPath()
    sep.move(to: NSPoint(x: rect.minX, y: titleBarRect.minY))
    sep.line(to: NSPoint(x: rect.maxX, y: titleBarRect.minY))
    sep.lineWidth = 0.5 * scale
    sep.stroke()

    // Tab bar
    if !tabs.isEmpty {
        let tabBarRect = NSRect(x: rect.minX, y: rect.maxY - titleBarH - tabBarH, width: rect.width, height: tabBarH)
        NSColor(srgbRed: 0.86, green: 0.86, blue: 0.89, alpha: 1.0).setFill()
        NSBezierPath(rect: tabBarRect).fill()

        let tabFont = NSFont.systemFont(ofSize: 11 * scale, weight: .medium)
        let tabW = rect.width / CGFloat(tabs.count)
        for (i, tab) in tabs.enumerated() {
            let tabRect = NSRect(x: rect.minX + CGFloat(i) * tabW, y: tabBarRect.minY, width: tabW, height: tabBarH)
            if i == selectedTab {
                NSColor(srgbRed: 0.28, green: 0.52, blue: 0.96, alpha: 0.18).setFill()
                NSBezierPath(rect: tabRect).fill()
            }
            let color = i == selectedTab
                ? NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1.0)
                : NSColor(srgbRed: 0.40, green: 0.40, blue: 0.44, alpha: 1.0)
            let ts2 = textSize(tab, font: tabFont)
            drawText(tab,
                     at: NSPoint(x: tabRect.midX - ts2.width / 2, y: tabBarRect.minY + (tabBarH - ts2.height) / 2),
                     font: tabFont, color: color)
        }
        NSColor.black.withAlphaComponent(0.10).setStroke()
        let sep2 = NSBezierPath()
        sep2.move(to: NSPoint(x: rect.minX, y: tabBarRect.minY))
        sep2.line(to: NSPoint(x: rect.maxX, y: tabBarRect.minY))
        sep2.lineWidth = 0.5 * scale
        sep2.stroke()
    }

    ctx.restoreGState()

    // Outer border
    NSColor.black.withAlphaComponent(0.12).setStroke()
    let outerBorder = NSBezierPath(roundedRect: rect, xRadius: 10 * scale, yRadius: 10 * scale)
    outerBorder.lineWidth = 0.5 * scale
    outerBorder.stroke()

    return rect.maxY - titleBarH - (tabs.isEmpty ? 0 : tabBarH)
}

// Draws a section header label.
func drawSectionHeader(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, scale: CGFloat) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 11 * scale, weight: .semibold)
    let color = NSColor(srgbRed: 0.40, green: 0.40, blue: 0.46, alpha: 1.0)
    drawText(text.uppercased(), at: NSPoint(x: x + 8 * scale, y: y), font: font, color: color)
    return 18 * scale
}

// Draws a rounded grouped-form card background.
func drawGroupedCard(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, scale: CGFloat) {
    let cardRect = NSRect(x: x, y: y, width: width, height: height)
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 8 * scale, yRadius: 8 * scale)
    NSColor.white.withAlphaComponent(0.80).setFill()
    cardPath.fill()
    NSColor.black.withAlphaComponent(0.06).setStroke()
    cardPath.lineWidth = 0.5 * scale
    cardPath.stroke()
}

// Draws a single row inside a grouped card. Returns the row height consumed.
func drawFormRow(label: String, value: String, x: CGFloat, y: CGFloat, width: CGFloat, rowH: CGFloat, scale: CGFloat, isLast: Bool = false) {
    let labelFont = NSFont.systemFont(ofSize: 12 * scale, weight: .regular)
    let valueFont = NSFont.systemFont(ofSize: 12 * scale, weight: .regular)
    let labelColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let valueColor = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0)
    drawText(label, at: NSPoint(x: x + 12 * scale, y: y + (rowH - textSize(label, font: labelFont).height) / 2),
             font: labelFont, color: labelColor)
    let vs = textSize(value, font: valueFont)
    drawText(value, at: NSPoint(x: x + width - 12 * scale - vs.width, y: y + (rowH - vs.height) / 2),
             font: valueFont, color: valueColor)
    if !isLast {
        NSColor.black.withAlphaComponent(0.07).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: x + 12 * scale, y: y))
        sep.line(to: NSPoint(x: x + width - 12 * scale, y: y))
        sep.lineWidth = 0.5 * scale
        sep.stroke()
    }
}

// Draws a toggle row (ON/OFF pill). Returns row height consumed.
func drawToggleRow(label: String, isOn: Bool, x: CGFloat, y: CGFloat, width: CGFloat, rowH: CGFloat, scale: CGFloat, isLast: Bool = false) {
    let labelFont = NSFont.systemFont(ofSize: 12 * scale, weight: .regular)
    let labelColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    drawText(label, at: NSPoint(x: x + 12 * scale, y: y + (rowH - textSize(label, font: labelFont).height) / 2),
             font: labelFont, color: labelColor)
    // Toggle pill
    let tw: CGFloat = 36 * scale
    let th: CGFloat = 20 * scale
    let tx = x + width - 12 * scale - tw
    let ty = y + (rowH - th) / 2
    let pillRect = NSRect(x: tx, y: ty, width: tw, height: th)
    let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: th / 2, yRadius: th / 2)
    if isOn {
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1.0).setFill()
    } else {
        NSColor(srgbRed: 0.78, green: 0.78, blue: 0.82, alpha: 1.0).setFill()
    }
    pillPath.fill()
    // Knob
    let knobR: CGFloat = th / 2 - 2 * scale
    let knobX = isOn ? tx + tw - knobR - 2 * scale : tx + knobR + 2 * scale
    let knobY = ty + th / 2
    let knob = NSBezierPath(ovalIn: NSRect(x: knobX - knobR, y: knobY - knobR, width: knobR * 2, height: knobR * 2))
    NSColor.white.setFill()
    knob.fill()
    if !isLast {
        NSColor.black.withAlphaComponent(0.07).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: x + 12 * scale, y: y))
        sep.line(to: NSPoint(x: x + width - 12 * scale, y: y))
        sep.lineWidth = 0.5 * scale
        sep.stroke()
    }
}

// Draws a status row with a green checkmark badge. Returns row height consumed.
func drawStatusRow(label: String, status: String, x: CGFloat, y: CGFloat, width: CGFloat, rowH: CGFloat, scale: CGFloat, isLast: Bool = false) {
    let labelFont = NSFont.systemFont(ofSize: 12 * scale, weight: .regular)
    let statusFont = NSFont.systemFont(ofSize: 11 * scale, weight: .semibold)
    let labelColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let statusColor = NSColor(srgbRed: 0.18, green: 0.70, blue: 0.30, alpha: 1.0)
    drawText(label, at: NSPoint(x: x + 12 * scale, y: y + (rowH - textSize(label, font: labelFont).height) / 2),
             font: labelFont, color: labelColor)
    let ss = textSize(status, font: statusFont)
    let sx = x + width - 12 * scale - ss.width - 18 * scale
    drawSymbol("checkmark.seal.fill", at: NSPoint(x: x + width - 12 * scale - ss.width - 18 * scale, y: y + (rowH - 14 * scale) / 2), fontSize: 14 * scale, color: statusColor)
    drawText(status, at: NSPoint(x: sx + 16 * scale, y: y + (rowH - ss.height) / 2), font: statusFont, color: statusColor)
    if !isLast {
        NSColor.black.withAlphaComponent(0.07).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: x + 12 * scale, y: y))
        sep.line(to: NSPoint(x: x + width - 12 * scale, y: y))
        sep.lineWidth = 0.5 * scale
        sep.stroke()
    }
}

// Draws a bordered button. Returns button width.
@discardableResult
func drawBorderedButton(label: String, x: CGFloat, y: CGFloat, height: CGFloat, scale: CGFloat, accent: Bool = false) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 11 * scale, weight: .medium)
    let ts = textSize(label, font: font)
    let bw = ts.width + 20 * scale
    let bh = height
    let bRect = NSRect(x: x, y: y, width: bw, height: bh)
    let bPath = NSBezierPath(roundedRect: bRect, xRadius: 5 * scale, yRadius: 5 * scale)
    if accent {
        NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1.0).setFill()
        bPath.fill()
        drawText(label, at: NSPoint(x: x + (bw - ts.width) / 2, y: y + (bh - ts.height) / 2), font: font, color: .white)
    } else {
        NSColor.white.withAlphaComponent(0.80).setFill()
        bPath.fill()
        NSColor.black.withAlphaComponent(0.14).setStroke()
        bPath.lineWidth = 0.5 * scale
        bPath.stroke()
        drawText(label, at: NSPoint(x: x + (bw - ts.width) / 2, y: y + (bh - ts.height) / 2),
                 font: font, color: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.20, alpha: 1.0))
    }
    return bw
}

// ── popup-screen.png ───────────────────────────────────────────────────────

let screenPopupCanvas = NSSize(width: 1200, height: 720)
let screenPopupImage = NSImage(size: screenPopupCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 2.0
    let popupW: CGFloat = 380 * scale
    let popupH: CGFloat = 112 * scale
    let popupOrigin = NSPoint(x: (rect.width - popupW) / 2, y: (rect.height - popupH) / 2)
    let popupRect = NSRect(origin: popupOrigin, size: NSSize(width: popupW, height: popupH))
    let popupPath = NSBezierPath(roundedRect: popupRect, xRadius: 12 * scale, yRadius: 12 * scale)

    drawShadow(for: popupPath, offset: NSSize(width: 0, height: -10 * scale), blur: 28 * scale, alpha: 0.32, fill: NSColor.white)

    NSGraphicsContext.current!.cgContext.saveGState()
    popupPath.addClip()
    let materialGrad = NSGradient(colors: [
        NSColor(srgbRed: 0.94, green: 0.94, blue: 0.96, alpha: 0.96),
        NSColor(srgbRed: 0.91, green: 0.91, blue: 0.94, alpha: 0.96)
    ])!
    materialGrad.draw(in: popupRect, angle: -90)
    NSColor.black.withAlphaComponent(0.06).setStroke()
    let border = NSBezierPath(roundedRect: popupRect, xRadius: 12 * scale, yRadius: 12 * scale)
    border.lineWidth = 0.5 * scale
    border.stroke()
    NSGraphicsContext.current!.cgContext.restoreGState()

    let pad: CGFloat = 14 * scale
    let secondaryColor = NSColor(srgbRed: 0.36, green: 0.36, blue: 0.40, alpha: 1.0)
    let primaryColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let headerFont = NSFont.systemFont(ofSize: 10 * scale, weight: .semibold)

    // Top row: text.viewfinder + "Recognized text"
    let topY = popupRect.maxY - pad - 10 * scale
    var x = popupRect.minX + pad
    let symW = drawSymbol("text.viewfinder", at: NSPoint(x: x, y: topY - 2 * scale), fontSize: 12 * scale, color: secondaryColor)
    x += symW + 5 * scale
    drawText("Recognized text", at: NSPoint(x: x, y: topY), font: headerFont, color: secondaryColor)

    // Body: OCR text
    let bodyFont = NSFont.systemFont(ofSize: 13 * scale, weight: .regular)
    let bodyY = popupRect.minY + pad + 32 * scale
    drawText(AppFixture.fixtureOCRText, at: NSPoint(x: popupRect.minX + pad, y: bodyY), font: bodyFont, color: primaryColor)

    // Bottom row: Copy | Translate (accent) | Retry — right-aligned
    let btnH: CGFloat = 22 * scale
    let btnY = popupRect.minY + pad - 2 * scale
    var bx = popupRect.maxX - pad

    // Retry (right-most, bordered)
    let retryFont = NSFont.systemFont(ofSize: 11 * scale, weight: .medium)
    let retryLabel = "Retry"
    let retryW = textSize(retryLabel, font: retryFont).width + 20 * scale
    bx -= retryW
    drawBorderedButton(label: retryLabel, x: bx, y: btnY, height: btnH, scale: scale, accent: false)
    bx -= 8 * scale

    // Translate (accent blue, filled)
    let translateLabel = "Translate"
    let translateW = textSize(translateLabel, font: retryFont).width + 20 * scale
    bx -= translateW
    drawBorderedButton(label: translateLabel, x: bx, y: btnY, height: btnH, scale: scale, accent: true)
    bx -= 8 * scale

    // Copy (bordered)
    let copyLabel = "Copy"
    let copyW = textSize(copyLabel, font: retryFont).width + 20 * scale
    bx -= copyW
    drawBorderedButton(label: copyLabel, x: bx, y: btnY, height: btnH, scale: scale, accent: false)

    // Caption below
    let cap = NSAttributedString(string: "Screen Translate — capture any region, OCR + translate in one step.", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85)
    ])
    let capSize = cap.size()
    cap.draw(at: NSPoint(x: (rect.width - capSize.width) / 2, y: popupRect.minY - 56))

    return true
}
try savePNG(screenPopupImage, to: "\(outDir)/popup-screen.png")
print("Wrote \(outDir)/popup-screen.png")

// ── settings-main.png ─────────────────────────────────────────────────────

let settingsMainCanvas = NSSize(width: 1440, height: 1120)
let settingsMainImage = NSImage(size: settingsMainCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 2.0
    let winW: CGFloat = 720 * scale
    let winH: CGFloat = 560 * scale
    let winRect = NSRect(x: (rect.width - winW) / 2, y: (rect.height - winH) / 2, width: winW, height: winH)

    let contentTopY = drawWindowChrome(in: winRect, title: "Settings", scale: scale, tabs: AppFixture.settingsTabs, selectedTab: AppFixture.tabMain)

    let contentRect = NSRect(x: winRect.minX, y: winRect.minY, width: winRect.width, height: contentTopY - winRect.minY)
    let cPad: CGFloat = 20 * scale
    let cardW = contentRect.width - cPad * 2
    let rowH: CGFloat = 34 * scale
    var curY = contentRect.maxY - cPad

    func section(_ header: String, rows: Int, draw: (CGFloat) -> Void) {
        curY -= 6 * scale
        curY -= drawSectionHeader(header, x: contentRect.minX + cPad, y: curY - 14 * scale, width: cardW, scale: scale)
        let cardH = CGFloat(rows) * rowH
        drawGroupedCard(x: contentRect.minX + cPad, y: curY - cardH, width: cardW, height: cardH, scale: scale)
        draw(curY - cardH)
        curY -= cardH + 2 * scale
    }

    // Section: Target language
    section("Target language", rows: 2) { cardY in
        drawToggleRow(label: "Auto-detect input language", isOn: false,
                      x: contentRect.minX + cPad, y: cardY + rowH, width: cardW, rowH: rowH, scale: scale)
        drawFormRow(label: "Target", value: AppFixture.targetLanguage,
                    x: contentRect.minX + cPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    // Section: Popup
    section("Popup", rows: 1) { cardY in
        drawFormRow(label: "Result font size", value: AppFixture.popupFontSize,
                    x: contentRect.minX + cPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    // Section: Limits
    section("Limits", rows: 2) { cardY in
        drawFormRow(label: "Max input characters", value: AppFixture.maxInputChars,
                    x: contentRect.minX + cPad, y: cardY + rowH, width: cardW, rowH: rowH, scale: scale)
        drawFormRow(label: "History size", value: AppFixture.historySize,
                    x: contentRect.minX + cPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    // Section: Startup
    section("Startup", rows: 1) { cardY in
        drawToggleRow(label: "Launch at login", isOn: true,
                      x: contentRect.minX + cPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    // Section: iCloud Drive sync
    section("iCloud Drive sync", rows: 2) { cardY in
        drawFormRow(label: "iCloud Drive", value: "iCloud Drive available",
                    x: contentRect.minX + cPad, y: cardY + rowH, width: cardW, rowH: rowH, scale: scale)
        drawToggleRow(label: "Sync settings & history via iCloud Drive", isOn: true,
                      x: contentRect.minX + cPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    // Section: Accessibility
    section("Accessibility", rows: 1) { cardY in
        drawStatusRow(label: "Accessibility", status: "Granted",
                      x: contentRect.minX + cPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    // Section: Screen Recording
    section("Screen Recording", rows: 1) { cardY in
        drawStatusRow(label: "Screen Recording", status: "Granted",
                      x: contentRect.minX + cPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    return true
}
try savePNG(settingsMainImage, to: "\(outDir)/settings-main.png")
print("Wrote \(outDir)/settings-main.png")

// ── settings-providers.png ────────────────────────────────────────────────

let settingsProvCanvas = NSSize(width: 1440, height: 1120)
let settingsProvImage = NSImage(size: settingsProvCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 2.0
    let winW: CGFloat = 720 * scale
    let winH: CGFloat = 560 * scale
    let winRect = NSRect(x: (rect.width - winW) / 2, y: (rect.height - winH) / 2, width: winW, height: winH)

    let contentTopY = drawWindowChrome(in: winRect, title: "Settings", scale: scale, tabs: AppFixture.settingsTabs, selectedTab: AppFixture.tabProviders)

    let contentRect = NSRect(x: winRect.minX, y: winRect.minY, width: winRect.width, height: contentTopY - winRect.minY)

    let sidebarW: CGFloat = 220 * scale
    let sidebarRect = NSRect(x: contentRect.minX, y: contentRect.minY, width: sidebarW, height: contentRect.height)
    NSColor(srgbRed: 0.88, green: 0.88, blue: 0.91, alpha: 1.0).setFill()
    NSBezierPath(rect: sidebarRect).fill()
    NSColor.black.withAlphaComponent(0.08).setStroke()
    let sideDiv = NSBezierPath()
    sideDiv.move(to: NSPoint(x: sidebarRect.maxX, y: sidebarRect.minY))
    sideDiv.line(to: NSPoint(x: sidebarRect.maxX, y: sidebarRect.maxY))
    sideDiv.lineWidth = 0.5 * scale
    sideDiv.stroke()

    struct Provider { let name: String; let badge: String; let active: Bool }
    let providers: [Provider] = [
        Provider(name: "Claude",               badge: "A key is stored", active: true),
        Provider(name: "OpenAI",               badge: "No key",          active: false),
        Provider(name: "Gemini",               badge: "No key",          active: false),
        Provider(name: "Google (Free)",        badge: "No key needed",   active: false),
        Provider(name: "Google Translate",     badge: "No key",          active: false),
        Provider(name: "DeepL",                badge: "No key",          active: false),
        Provider(name: "Microsoft Translator", badge: "No key",          active: false)
    ]
    let provRowH: CGFloat = 40 * scale
    let provNameFont = NSFont.systemFont(ofSize: 12 * scale, weight: .medium)
    let badgeFont = NSFont.systemFont(ofSize: 9 * scale, weight: .regular)
    let sideTopY = contentRect.maxY - 8 * scale
    for (i, prov) in providers.enumerated() {
        let rowY = sideTopY - CGFloat(i + 1) * provRowH
        if prov.active {
            NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 0.15).setFill()
            NSBezierPath(rect: NSRect(x: sidebarRect.minX, y: rowY, width: sidebarW, height: provRowH)).fill()
        }
        let nameColor = prov.active
            ? NSColor(srgbRed: 0.10, green: 0.30, blue: 0.85, alpha: 1.0)
            : NSColor(srgbRed: 0.15, green: 0.15, blue: 0.20, alpha: 1.0)
        let nameY = rowY + provRowH - 14 * scale - 6 * scale
        if prov.active {
            drawSymbol("star.fill", at: NSPoint(x: sidebarRect.minX + 10 * scale, y: nameY - 1 * scale), fontSize: 11 * scale,
                       color: NSColor(srgbRed: 1.0, green: 0.75, blue: 0.10, alpha: 1.0))
        }
        drawText(prov.name, at: NSPoint(x: sidebarRect.minX + 26 * scale, y: nameY), font: provNameFont, color: nameColor)
        let badgeColor = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0)
        drawText(prov.badge, at: NSPoint(x: sidebarRect.minX + 26 * scale, y: rowY + 6 * scale), font: badgeFont, color: badgeColor)
    }

    // Detail panel
    let detailX = sidebarRect.maxX
    let detailW = contentRect.width - sidebarW
    let dPad: CGFloat = 20 * scale
    let cardW = detailW - dPad * 2
    let rowH: CGFloat = 34 * scale
    var curY = contentRect.maxY - dPad

    let provHeaderFont = NSFont.systemFont(ofSize: 16 * scale, weight: .semibold)
    let provHeaderColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let secondaryColor = NSColor(srgbRed: 0.36, green: 0.36, blue: 0.40, alpha: 1.0)
    curY -= 24 * scale
    drawText("Claude", at: NSPoint(x: detailX + dPad, y: curY), font: provHeaderFont, color: provHeaderColor)
    curY -= 10 * scale

    // Capability line
    let capFont = NSFont.systemFont(ofSize: 10 * scale, weight: .regular)
    let capW = drawSymbol("cpu", at: NSPoint(x: detailX + dPad, y: curY - 1 * scale), fontSize: 12 * scale, color: secondaryColor)
    drawText("Translate · Fix grammar · Rewrite · Explain · Screen Translate",
             at: NSPoint(x: detailX + dPad + capW + 4 * scale, y: curY), font: capFont, color: secondaryColor)
    curY -= 14 * scale

    func detailSection(_ header: String, rows: Int, draw: (CGFloat) -> Void) {
        curY -= 6 * scale
        curY -= drawSectionHeader(header, x: detailX + dPad, y: curY - 14 * scale, width: cardW, scale: scale)
        let cardH = CGFloat(rows) * rowH
        drawGroupedCard(x: detailX + dPad, y: curY - cardH, width: cardW, height: cardH, scale: scale)
        draw(curY - cardH)
        curY -= cardH + 2 * scale
    }

    detailSection("API key", rows: 1) { cardY in
        drawFormRow(label: "API key", value: "A key is stored",
                    x: detailX + dPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    detailSection("Endpoint", rows: 1) { cardY in
        drawFormRow(label: "Base URL", value: AppFixture.claudeBaseURL,
                    x: detailX + dPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }
    let captionFont = NSFont.systemFont(ofSize: 9 * scale, weight: .regular)
    let captionColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.60, alpha: 1.0)
    drawText("Default: https://api.anthropic.com", at: NSPoint(x: detailX + dPad + 8 * scale, y: curY - 2 * scale), font: captionFont, color: captionColor)
    curY -= 12 * scale

    detailSection("Model", rows: 1) { cardY in
        drawFormRow(label: "Model", value: AppFixture.claudeModel,
                    x: detailX + dPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    detailSection("Fallback", rows: 1) { cardY in
        drawFormRow(label: "If Claude fails", value: "Don't fall back",
                    x: detailX + dPad, y: cardY, width: cardW, rowH: rowH, scale: scale, isLast: true)
    }

    curY -= 8 * scale
    drawBorderedButton(label: "Save", x: detailX + dPad, y: curY - 26 * scale, height: 26 * scale, scale: scale, accent: true)

    return true
}
try savePNG(settingsProvImage, to: "\(outDir)/settings-providers.png")
print("Wrote \(outDir)/settings-providers.png")

// ── settings-shortcuts.png ────────────────────────────────────────────────

let settingsShortcutsCanvas = NSSize(width: 1440, height: 1120)
let settingsShortcutsImage = NSImage(size: settingsShortcutsCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 2.0
    let winW: CGFloat = 720 * scale
    let winH: CGFloat = 560 * scale
    let winRect = NSRect(x: (rect.width - winW) / 2, y: (rect.height - winH) / 2, width: winW, height: winH)

    let contentTopY = drawWindowChrome(in: winRect, title: "Settings", scale: scale, tabs: AppFixture.settingsTabs, selectedTab: AppFixture.tabShortcuts)

    let contentRect = NSRect(x: winRect.minX, y: winRect.minY, width: winRect.width, height: contentTopY - winRect.minY)
    let cPad: CGFloat = 20 * scale
    let cardW = contentRect.width - cPad * 2
    let rowH: CGFloat = 40 * scale

    struct Shortcut { let symbol: String; let name: String; let hotkey: String? }
    let shortcuts: [Shortcut] = [
        Shortcut(symbol: "globe",                name: "Translate",        hotkey: "⌥T"),
        Shortcut(symbol: "checkmark.seal",       name: "Fix grammar",      hotkey: nil),
        Shortcut(symbol: "wand.and.stars",       name: "Rewrite",          hotkey: nil),
        Shortcut(symbol: "text.magnifyingglass", name: "Explain",          hotkey: nil),
        Shortcut(symbol: "camera.viewfinder",    name: "Screen Translate", hotkey: nil)
    ]

    var curY = contentRect.maxY - cPad
    curY -= 6 * scale
    curY -= drawSectionHeader("Shortcuts", x: contentRect.minX + cPad, y: curY - 14 * scale, width: cardW, scale: scale)

    let cardH = CGFloat(shortcuts.count) * rowH
    let cardY = curY - cardH
    drawGroupedCard(x: contentRect.minX + cPad, y: cardY, width: cardW, height: cardH, scale: scale)

    let nameFont = NSFont.systemFont(ofSize: 12 * scale, weight: .regular)
    let nameColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let hotkeyFont = NSFont.systemFont(ofSize: 11 * scale, weight: .medium)
    let hotkeyBgColor = NSColor(srgbRed: 0.85, green: 0.85, blue: 0.88, alpha: 1.0)
    let hotkeyTextColor = NSColor(srgbRed: 0.20, green: 0.20, blue: 0.26, alpha: 1.0)
    let notSetBgColor = NSColor(srgbRed: 0.88, green: 0.88, blue: 0.92, alpha: 1.0)
    let notSetTextColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.60, alpha: 1.0)
    let symbolColor = NSColor(srgbRed: 0.40, green: 0.40, blue: 0.46, alpha: 1.0)

    for (i, sc) in shortcuts.enumerated() {
        let ry = cardY + CGFloat(shortcuts.count - 1 - i) * rowH
        let isLast = i == shortcuts.count - 1
        drawSymbol(sc.symbol, at: NSPoint(x: contentRect.minX + cPad + 12 * scale, y: ry + (rowH - 14 * scale) / 2), fontSize: 14 * scale, color: symbolColor)
        drawText(sc.name, at: NSPoint(x: contentRect.minX + cPad + 32 * scale, y: ry + (rowH - textSize(sc.name, font: nameFont).height) / 2), font: nameFont, color: nameColor)

        if let hotkey = sc.hotkey {
            let hts = textSize(hotkey, font: hotkeyFont)
            let pillW = hts.width + 14 * scale
            let pillH: CGFloat = 20 * scale
            let pillX = contentRect.minX + cPad + cardW - 12 * scale - pillW
            let pillY = ry + (rowH - pillH) / 2
            let pillRect = NSRect(x: pillX, y: pillY, width: pillW, height: pillH)
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 4 * scale, yRadius: 4 * scale)
            hotkeyBgColor.setFill()
            pillPath.fill()
            NSColor.black.withAlphaComponent(0.10).setStroke()
            pillPath.lineWidth = 0.5 * scale
            pillPath.stroke()
            drawText(hotkey, at: NSPoint(x: pillX + 7 * scale, y: pillY + (pillH - hts.height) / 2), font: hotkeyFont, color: hotkeyTextColor)
        } else {
            let notSetLabel = "Not set"
            let hts = textSize(notSetLabel, font: hotkeyFont)
            let pillW = hts.width + 14 * scale
            let pillH: CGFloat = 20 * scale
            let pillX = contentRect.minX + cPad + cardW - 12 * scale - pillW
            let pillY = ry + (rowH - pillH) / 2
            let pillRect = NSRect(x: pillX, y: pillY, width: pillW, height: pillH)
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 4 * scale, yRadius: 4 * scale)
            notSetBgColor.setFill()
            pillPath.fill()
            NSColor.black.withAlphaComponent(0.06).setStroke()
            pillPath.lineWidth = 0.5 * scale
            pillPath.stroke()
            drawText(notSetLabel, at: NSPoint(x: pillX + 7 * scale, y: pillY + (pillH - hts.height) / 2), font: hotkeyFont, color: notSetTextColor)
        }

        if !isLast {
            NSColor.black.withAlphaComponent(0.07).setStroke()
            let sep = NSBezierPath()
            sep.move(to: NSPoint(x: contentRect.minX + cPad + 12 * scale, y: ry))
            sep.line(to: NSPoint(x: contentRect.minX + cPad + cardW - 12 * scale, y: ry))
            sep.lineWidth = 0.5 * scale
            sep.stroke()
        }
    }

    let footerFont = NSFont.systemFont(ofSize: 11 * scale, weight: .regular)
    let footerColor = NSColor(srgbRed: 0.50, green: 0.50, blue: 0.56, alpha: 1.0)
    let footerText = "Click a shortcut field, then press a key combination. Use any of ⌃ ⌥ ⇧ ⌘ plus a key. Esc cancels recording. ✕ removes the shortcut."
    drawText(footerText, at: NSPoint(x: contentRect.minX + cPad + 12 * scale, y: cardY - 20 * scale), font: footerFont, color: footerColor)

    return true
}
try savePNG(settingsShortcutsImage, to: "\(outDir)/settings-shortcuts.png")
print("Wrote \(outDir)/settings-shortcuts.png")

// ── settings-about.png ────────────────────────────────────────────────────

let settingsAboutCanvas = NSSize(width: 1440, height: 1120)
let settingsAboutImage = NSImage(size: settingsAboutCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 2.0
    let winW: CGFloat = 720 * scale
    let winH: CGFloat = 560 * scale
    let winRect = NSRect(x: (rect.width - winW) / 2, y: (rect.height - winH) / 2, width: winW, height: winH)

    let contentTopY = drawWindowChrome(in: winRect, title: "Settings", scale: scale, tabs: AppFixture.settingsTabs, selectedTab: AppFixture.tabAbout)

    let contentRect = NSRect(x: winRect.minX, y: winRect.minY, width: winRect.width, height: contentTopY - winRect.minY)
    let hPad: CGFloat = 32 * scale
    let contentW = contentRect.width - hPad * 2

    // Derive project root: outDir is <root>/public-repo/docs/screenshots → 3 levels up
    let projectRoot = URL(fileURLWithPath: outDir)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path

    // Draws centered word-wrapped text; returns height consumed.
    func drawCenteredWrapped(_ text: String, font: NSFont, color: NSColor, atY y: CGFloat) -> CGFloat {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let bounded = attrStr.boundingRect(
            with: NSSize(width: contentW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = NSRect(x: contentRect.minX + hPad, y: y - bounded.height,
                              width: contentW, height: bounded.height)
        attrStr.draw(with: drawRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        return bounded.height
    }

    var curY = contentTopY - 16 * scale

    // App icon (120pt @2x = 240px)
    let iconSize: CGFloat = 120 * scale
    let iconPath = "\(projectRoot)/App/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png"
    let iconX = contentRect.midX - iconSize / 2
    curY -= iconSize
    if let iconImage = NSImage(contentsOfFile: iconPath) {
        let iconRect = NSRect(x: iconX, y: curY, width: iconSize, height: iconSize)
        iconImage.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    } else {
        drawSymbol("globe", at: NSPoint(x: iconX + iconSize * 0.1, y: curY + iconSize * 0.1),
                   fontSize: iconSize * 0.8, color: NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1.0))
    }
    curY -= 12 * scale

    // App name
    let appNameH = drawCenteredWrapped("LingoPop",
        font: NSFont.systemFont(ofSize: 26 * scale, weight: .semibold),
        color: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
        atY: curY)
    curY -= appNameH + 4 * scale

    // Version
    let versionH = drawCenteredWrapped("Version \(AppFixture.version)",
        font: NSFont.systemFont(ofSize: 11 * scale, weight: .regular),
        color: NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0),
        atY: curY)
    curY -= versionH + 14 * scale

    // Horizontal divider (~60% width)
    let divW = contentRect.width * 0.6
    let divX = contentRect.midX - divW / 2
    NSColor.black.withAlphaComponent(0.10).setStroke()
    let divPath = NSBezierPath()
    divPath.move(to: NSPoint(x: divX, y: curY))
    divPath.line(to: NSPoint(x: divX + divW, y: curY))
    divPath.lineWidth = 0.5 * scale
    divPath.stroke()
    curY -= 14 * scale

    // Body paragraph
    let bodyH = drawCenteredWrapped(
        "Select text anywhere on your Mac, press a shortcut, and get an instant AI translation, grammar fix, or rewrite in a popup near your cursor.",
        font: NSFont.systemFont(ofSize: 13 * scale, weight: .regular),
        color: NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0),
        atY: curY)
    curY -= bodyH + 10 * scale

    // Secondary body paragraph
    let secH = drawCenteredWrapped(
        "Supports Claude, OpenAI, Gemini, and Google Translate. API keys are stored locally in an encrypted file. Settings sync between Macs via iCloud Drive.",
        font: NSFont.systemFont(ofSize: 12 * scale, weight: .regular),
        color: NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0),
        atY: curY)
    curY -= secH + 10 * scale

    // Privacy Policy link
    _ = drawCenteredWrapped("Privacy Policy",
        font: NSFont.systemFont(ofSize: 12 * scale, weight: .regular),
        color: NSColor.linkColor,
        atY: curY)

    return true
}
try savePNG(settingsAboutImage, to: "\(outDir)/settings-about.png")
print("Wrote \(outDir)/settings-about.png")

// ── history.png ───────────────────────────────────────────────────────────

let historyCanvas = NSSize(width: 960, height: 720)
let historyImage = NSImage(size: historyCanvas, flipped: false) { rect in
    drawDesktop(in: rect)

    let scale: CGFloat = 2.0
    let winW: CGFloat = 480 * scale
    let winH: CGFloat = 360 * scale
    let winRect = NSRect(x: (rect.width - winW) / 2, y: (rect.height - winH) / 2, width: winW, height: winH)

    let contentTopY = drawWindowChrome(in: winRect, title: "History", scale: scale, tabs: [], selectedTab: -1)
    let contentRect = NSRect(x: winRect.minX, y: winRect.minY, width: winRect.width, height: contentTopY - winRect.minY)

    let cPad: CGFloat = 12 * scale

    // Search bar
    let searchH: CGFloat = 26 * scale
    let searchY = contentRect.maxY - cPad - searchH
    let searchRect = NSRect(x: contentRect.minX + cPad, y: searchY, width: contentRect.width - cPad * 2, height: searchH)
    let searchPath = NSBezierPath(roundedRect: searchRect, xRadius: 6 * scale, yRadius: 6 * scale)
    NSColor.white.withAlphaComponent(0.80).setFill()
    searchPath.fill()
    NSColor.black.withAlphaComponent(0.10).setStroke()
    searchPath.lineWidth = 0.5 * scale
    searchPath.stroke()
    drawSymbol("magnifyingglass", at: NSPoint(x: searchRect.minX + 6 * scale, y: searchRect.minY + 5 * scale), fontSize: 12 * scale,
               color: NSColor(srgbRed: 0.55, green: 0.55, blue: 0.60, alpha: 1.0))
    let phFont = NSFont.systemFont(ofSize: 11 * scale, weight: .regular)
    drawText("Search history", at: NSPoint(x: searchRect.minX + 22 * scale, y: searchRect.minY + (searchH - textSize("Search history", font: phFont).height) / 2),
             font: phFont, color: NSColor(srgbRed: 0.60, green: 0.60, blue: 0.65, alpha: 1.0))
    drawSymbol("trash", at: NSPoint(x: searchRect.maxX - 20 * scale, y: searchRect.minY + 5 * scale), fontSize: 12 * scale,
               color: NSColor(srgbRed: 0.55, green: 0.55, blue: 0.60, alpha: 1.0))

    // History entries
    struct HistEntry { let op: String; let lang: String; let provider: String; let time: String; let original: String; let translated: String }
    let entries: [HistEntry] = [
        HistEntry(op: "Translation", lang: "Russian → Ukrainian", provider: "Claude", time: "Jun 9, 2026, 3:15 PM",
                  original: "Выберите текст в любом месте на вашем Mac",
                  translated: "Виберіть текст будь-де на вашому Mac"),
        HistEntry(op: "Grammar fix", lang: "", provider: "Claude", time: "Jun 9, 2026, 2:50 PM",
                  original: "the app works great and is very usefull",
                  translated: "The app works great and is very useful"),
        HistEntry(op: "Translation", lang: "French → Ukrainian", provider: "Claude", time: "Jun 9, 2026, 2:30 PM",
                  original: AppFixture.fixtureOCRText,
                  translated: "Привіт, як ви сьогодні?")
    ]

    let entryH: CGFloat = 64 * scale
    let listTopY = searchY - 8 * scale
    let metaFont = NSFont.systemFont(ofSize: 9 * scale, weight: .regular)
    let origFont = NSFont.systemFont(ofSize: 12 * scale, weight: .regular)
    let translFont = NSFont.systemFont(ofSize: 13 * scale, weight: .regular)
    let metaColor = NSColor(srgbRed: 0.55, green: 0.55, blue: 0.60, alpha: 1.0)
    let origColor = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0)
    let translColor = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.14, alpha: 1.0)
    let opBlueBg = NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 0.12)
    let opBlueText = NSColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1.0)
    let grayBg = NSColor(srgbRed: 0.92, green: 0.92, blue: 0.95, alpha: 1.0)
    let grayText = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1.0)
    let pillFont = NSFont.systemFont(ofSize: 9 * scale, weight: .semibold)
    let pillH: CGFloat = 14 * scale

    func drawBadgePill(_ text: String, atX px: CGFloat, atY py: CGFloat, bg: NSColor, fg: NSColor) -> CGFloat {
        let ts = textSize(text, font: pillFont)
        let pw = ts.width + 8 * scale
        let pillRect = NSRect(x: px, y: py, width: pw, height: pillH)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillH / 2, yRadius: pillH / 2)
        bg.setFill()
        pillPath.fill()
        drawText(text, at: NSPoint(x: px + 4 * scale, y: py + (pillH - ts.height) / 2), font: pillFont, color: fg)
        return pw
    }

    for (i, entry) in entries.enumerated() {
        let ey = listTopY - CGFloat(i + 1) * entryH
        NSColor.black.withAlphaComponent(0.07).setStroke()
        let sep = NSBezierPath()
        sep.move(to: NSPoint(x: contentRect.minX + cPad, y: ey + entryH))
        sep.line(to: NSPoint(x: contentRect.maxX - cPad, y: ey + entryH))
        sep.lineWidth = 0.5 * scale
        sep.stroke()

        let rx = contentRect.minX + cPad + 8 * scale
        let metaY = ey + entryH - pillH - 4 * scale

        // Badges row
        var bx = rx
        let opW = drawBadgePill(entry.op, atX: bx, atY: metaY, bg: opBlueBg, fg: opBlueText)
        bx += opW + 4 * scale
        if !entry.lang.isEmpty {
            let langW = drawBadgePill(entry.lang, atX: bx, atY: metaY, bg: grayBg, fg: grayText)
            bx += langW + 4 * scale
        }
        _ = drawBadgePill(entry.provider, atX: bx, atY: metaY, bg: grayBg, fg: grayText)

        // Timestamp right-aligned
        let timeStr = entry.time
        let timeSize = textSize(timeStr, font: metaFont)
        drawText(timeStr, at: NSPoint(x: contentRect.maxX - cPad - 8 * scale - timeSize.width, y: metaY + (pillH - timeSize.height) / 2), font: metaFont, color: metaColor)

        // Ellipsis button
        drawSymbol("ellipsis.circle", at: NSPoint(x: contentRect.maxX - cPad - 20 * scale, y: ey + entryH / 2 - 7 * scale), fontSize: 14 * scale, color: metaColor)

        // Original text (gray, smaller)
        let origText = entry.original.count > 48 ? String(entry.original.prefix(48)) + "…" : entry.original
        drawText(origText, at: NSPoint(x: rx, y: ey + 26 * scale), font: origFont, color: origColor)

        // Translated text (dark, larger)
        let translText = entry.translated.count > 48 ? String(entry.translated.prefix(48)) + "…" : entry.translated
        drawText(translText, at: NSPoint(x: rx, y: ey + 8 * scale), font: translFont, color: translColor)
    }

    return true
}
try savePNG(historyImage, to: "\(outDir)/history.png")
print("Wrote \(outDir)/history.png")

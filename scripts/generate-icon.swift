#!/usr/bin/env swift
// Generates a 1024x1024 PNG app icon for LingoPop.
// Usage: swift scripts/generate-icon.swift <output.png>

import AppKit
import CoreGraphics

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon_1024.png"

let side: CGFloat = 1024
let cornerRadius: CGFloat = 229  // ~22.37% — macOS squircle approximation

let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    // ── Background squircle ───────────────────────────────────────────
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    bgPath.addClip()

    // Main diagonal gradient (deep purple → indigo → blue)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.42, green: 0.20, blue: 0.95, alpha: 1.0),
        NSColor(srgbRed: 0.32, green: 0.16, blue: 0.78, alpha: 1.0),
        NSColor(srgbRed: 0.18, green: 0.10, blue: 0.52, alpha: 1.0)
    ], atLocations: [0.0, 0.55, 1.0], colorSpace: .sRGB)!
    gradient.draw(in: rect, angle: -65)

    // Subtle top highlight for that macOS sheen
    let highlight = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.18),
        NSColor.white.withAlphaComponent(0.04),
        NSColor.clear
    ], atLocations: [0.0, 0.4, 1.0], colorSpace: .sRGB)!
    highlight.draw(in: rect, angle: -90)

    // ── Speech bubble ─────────────────────────────────────────────────
    let bubbleInset: CGFloat = 150
    let bubbleRect = rect.insetBy(dx: bubbleInset, dy: bubbleInset).offsetBy(dx: 0, dy: 30)
    let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 140, yRadius: 140)

    // Bubble tail (little pointer at lower-left)
    let tail = NSBezierPath()
    let tailBase = NSPoint(x: bubbleRect.minX + 220, y: bubbleRect.minY + 30)
    tail.move(to: tailBase)
    tail.line(to: NSPoint(x: bubbleRect.minX + 90, y: bubbleRect.minY - 100))
    tail.line(to: NSPoint(x: bubbleRect.minX + 320, y: bubbleRect.minY + 30))
    tail.close()
    bubble.append(tail)
    bubble.windingRule = .nonZero

    // Drop shadow under bubble
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: NSColor.black.withAlphaComponent(0.30).cgColor)
    NSColor.white.setFill()
    bubble.fill()
    ctx.restoreGState()

    // Inner subtle gradient inside bubble for depth
    ctx.saveGState()
    bubble.addClip()
    let bubbleShine = NSGradient(colors: [
        NSColor.white,
        NSColor(white: 0.96, alpha: 1.0)
    ])!
    bubbleShine.draw(in: bubbleRect, angle: -90)
    ctx.restoreGState()

    // ── Letters "AЇ" — Latin + Cyrillic to evoke translation ──────────
    let textColor = NSColor(srgbRed: 0.20, green: 0.10, blue: 0.55, alpha: 1.0)
    let fontSize: CGFloat = 380
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: textColor,
        .kern: -10
    ]
    let text = NSAttributedString(string: "AЇ", attributes: attrs)
    let textSize = text.size()
    let textOrigin = NSPoint(
        x: bubbleRect.midX - textSize.width / 2,
        y: bubbleRect.midY - textSize.height / 2 + 20
    )
    text.draw(at: textOrigin)

    // Small arrow below letters to suggest translation
    let arrowColor = NSColor(srgbRed: 0.42, green: 0.20, blue: 0.95, alpha: 0.9)
    arrowColor.setFill()
    let arrowY = bubbleRect.midY - 210
    let arrowPath = NSBezierPath()
    arrowPath.move(to: NSPoint(x: bubbleRect.midX - 100, y: arrowY))
    arrowPath.line(to: NSPoint(x: bubbleRect.midX + 100, y: arrowY))
    arrowPath.line(to: NSPoint(x: bubbleRect.midX + 75, y: arrowY + 30))
    arrowPath.move(to: NSPoint(x: bubbleRect.midX + 100, y: arrowY))
    arrowPath.line(to: NSPoint(x: bubbleRect.midX + 75, y: arrowY - 30))
    arrowPath.lineWidth = 18
    arrowPath.lineCapStyle = .round
    arrowPath.lineJoinStyle = .round
    arrowColor.setStroke()
    arrowPath.stroke()

    return true
}

guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Failed to render CGImage")
    exit(1)
}
let bitmap = NSBitmapImageRep(cgImage: cgImage)
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to encode PNG")
    exit(1)
}
try data.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")

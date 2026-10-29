// Native macOS screenshot renderer — uses real SwiftUI/AppKit components.
// Compile: swiftc -O -o render-screenshots UI/HistoryMenuItemView.swift scripts/render-screenshots.swift -framework AppKit -framework SwiftUI

import AppKit
import SwiftUI

// MARK: - Fixtures

enum AppFixture {
    static let version = "0.3.2"
    static let targetLanguage = "Ukrainian"
    static let claudeModel = "claude-haiku-4-5"
    static let claudeBaseURL = "https://api.anthropic.com"
    static let translated = "Дякую за швидку відповідь, передам команді."
    static let ocrText = "Bonjour, comment allez-vous aujourd'hui?"
    static let settingsTabs = ["Main", "Providers", "Shortcuts", "Usage", "Magic", "About"]
}

// MARK: - Snapshot helpers

func snapshotView(_ view: NSView, scale: CGFloat = 2.0) -> NSImage {
    view.layoutSubtreeIfNeeded()
    let bounds = view.bounds
    guard bounds.width > 0, bounds.height > 0 else {
        return NSImage(size: NSSize(width: 1, height: 1))
    }
    let rep = view.bitmapImageRepForCachingDisplay(in: bounds)!
    rep.size = bounds.size
    view.cacheDisplay(in: bounds, to: rep)
    let image = NSImage(size: bounds.size)
    image.addRepresentation(rep)
    if scale == 1.0 { return image }
    let scaled = NSImage(size: NSSize(width: bounds.width * scale, height: bounds.height * scale))
    scaled.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: bounds.width * scale, height: bounds.height * scale),
               from: .zero, operation: .copy, fraction: 1.0)
    scaled.unlockFocus()
    return scaled
}

func snapshotSwiftUI<V: View>(_ view: V, scale: CGFloat = 2.0) -> NSImage {
    let hosting = NSHostingView(rootView: view)
    let fit = hosting.fittingSize
    hosting.setFrameSize(NSSize(width: max(fit.width, 1), height: max(fit.height, 1)))
    hosting.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
    return snapshotView(hosting, scale: scale)
}

// MARK: - Window chrome (native-looking title bar for README composites)

struct MacWindowChrome<Content: View>: View {
    let title: String
    let width: CGFloat
    let contentHeight: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1, green: 0.73, blue: 0.16)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.20, green: 0.78, blue: 0.35)).frame(width: 12, height: 12)
                }
                .padding(.leading, 12)
                Spacer()
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Color.clear.frame(width: 68, height: 1)
            }
            .frame(height: 28)
            .background(Color(nsColor: .windowBackgroundColor))

            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.5)

            content()
                .frame(width: width, height: contentHeight)
        }
        .frame(width: width, height: contentHeight + 28)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.32), radius: 28, x: 0, y: 14)
    }
}

func snapshotChromeWindow<V: View>(
    title: String,
    width: CGFloat,
    contentHeight: CGFloat,
    @ViewBuilder content: @escaping () -> V
) -> NSImage {
    let view = MacWindowChrome(title: title, width: width, contentHeight: contentHeight, content: content)
    return snapshotSwiftUI(view.frame(width: width, height: contentHeight + 28))
}

func snapshotHostedWindow<V: View>(
    _ view: V,
    title: String,
    contentSize: NSSize,
    styleMask: NSWindow.StyleMask = [.titled, .closable]
) -> NSImage {
    snapshotChromeWindow(title: title, width: contentSize.width, contentHeight: contentSize.height) {
        view
    }
}

func drawDesktop(in rect: NSRect) {
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.18, green: 0.22, blue: 0.34, alpha: 1.0),
        NSColor(srgbRed: 0.36, green: 0.28, blue: 0.52, alpha: 1.0),
        NSColor(srgbRed: 0.55, green: 0.30, blue: 0.62, alpha: 1.0)
    ], atLocations: [0.0, 0.6, 1.0], colorSpace: .sRGB)!
    gradient.draw(in: rect, angle: -65)
}

func compositeOnDesktop(content: NSImage, canvasSize: NSSize, caption: String? = nil) -> NSImage {
    let canvas = NSImage(size: canvasSize)
    canvas.lockFocus()
    drawDesktop(in: NSRect(origin: .zero, size: canvasSize))

    var cw = content.size.width, ch = content.size.height
    let maxW = canvasSize.width * 0.72
    let maxH = canvasSize.height * 0.80
    let fitScale = min(maxW / cw, maxH / ch, 1.0)
    cw *= fitScale
    ch *= fitScale

    let x = (canvasSize.width - cw) / 2
    let y = (canvasSize.height - ch) / 2

    // Soft shadow under the window
    let shadowRect = NSRect(x: x + 6, y: y - 10, width: cw, height: ch)
    let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: 10, yRadius: 10)
    NSColor.black.withAlphaComponent(0.28).setFill()
    shadowPath.fill()

    content.draw(
        in: NSRect(x: x, y: y, width: cw, height: ch),
        from: NSRect(origin: .zero, size: content.size),
        operation: .sourceOver,
        fraction: 1.0
    )

    if let caption {
        let cap = NSAttributedString(string: caption, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ])
        let cs = cap.size()
        cap.draw(at: NSPoint(x: (canvasSize.width - cs.width) / 2, y: max(24, y - 56)))
    }
    canvas.unlockFocus()
    return canvas
}

func savePNG(_ image: NSImage, to path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "screenshot", code: 1)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Menu (native AppKit)

final class OperationMenuRowView: NSView {
    init(title: String, symbol: String, shortcut: String, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: StatusMenuMetrics.rowHeight))
        let font = NSFont.menuFont(ofSize: 0)
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let iv = NSImageView(image: img)
            iv.frame = NSRect(x: StatusMenuMetrics.horizontalInset, y: 3,
                              width: StatusMenuMetrics.iconSize, height: StatusMenuMetrics.iconSize)
            iv.contentTintColor = .labelColor
            addSubview(iv)
        }
        let label = NSTextField(labelWithString: title)
        label.font = font
        label.frame = NSRect(x: StatusMenuMetrics.titleLeading, y: 2,
                             width: width - StatusMenuMetrics.titleLeading - 60, height: 18)
        addSubview(label)
        if !shortcut.isEmpty {
            let sc = NSTextField(labelWithString: shortcut)
            sc.font = font
            sc.textColor = .tertiaryLabelColor
            sc.alignment = .right
            let sw = (shortcut as NSString).size(withAttributes: [.font: font]).width
            sc.frame = NSRect(x: width - StatusMenuMetrics.horizontalInset - sw, y: 2, width: sw, height: 18)
            addSubview(sc)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

final class SubmenuRowView: NSView {
    init(title: String, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: StatusMenuMetrics.rowHeight))
        let font = NSFont.menuFont(ofSize: 0)
        let label = NSTextField(labelWithString: title)
        label.font = font
        label.frame = NSRect(x: StatusMenuMetrics.horizontalInset + 10, y: 2,
                             width: width - 40, height: 18)
        addSubview(label)
        if let img = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            let iv = NSImageView(image: img)
            iv.frame = NSRect(x: width - 22, y: 4, width: 12, height: 12)
            iv.contentTintColor = .tertiaryLabelColor
            addSubview(iv)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

final class CommandRowView: NSView {
    init(title: String, shortcut: String, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: StatusMenuMetrics.rowHeight))
        let font = NSFont.menuFont(ofSize: 0)
        let label = NSTextField(labelWithString: title)
        label.font = font
        label.frame = NSRect(x: StatusMenuMetrics.horizontalInset + 10, y: 2,
                             width: width - 80, height: 18)
        addSubview(label)
        let sc = NSTextField(labelWithString: shortcut)
        sc.font = font
        sc.textColor = .tertiaryLabelColor
        sc.alignment = .right
        let sw = (shortcut as NSString).size(withAttributes: [.font: font]).width
        sc.frame = NSRect(x: width - StatusMenuMetrics.horizontalInset - sw, y: 2, width: sw, height: 18)
        addSubview(sc)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}

final class MenuSeparatorView: NSView {
    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 9))
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let y = bounds.midY
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 10, y: y))
        path.line(to: NSPoint(x: bounds.maxX - 10, y: y))
        path.lineWidth = 1
        path.stroke()
    }
}

func computeMenuWidth() -> CGFloat {
    let font = NSFont.menuFont(ofSize: 0)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    var maxW: CGFloat = 0
    let header = "Select the clip you want to add to your clipboard"
    maxW = max(maxW, (header as NSString).size(withAttributes: attrs).width)
    let recents = [
        "Thanks for the quick reply, I'll pass it to the team. → Дякую за швидку відповідь, передам команді.",
        "the app works great and is very usefull → The app works great and is very useful",
        "Bonjour, comment allez-vous aujourd'hui? → Hello, how are you today?"
    ]
    for r in recents { maxW = max(maxW, (r as NSString).size(withAttributes: attrs).width) }
    for (title, _) in [("Translate", "⌥T"), ("Fix grammar", ""), ("Target: Ukrainian", ""), ("History…", "⌘H")] {
        maxW = max(maxW, (title as NSString).size(withAttributes: attrs).width + 80)
    }
    return min(520, max(300, maxW + StatusMenuMetrics.horizontalInset * 2 + 50))
}

func buildMenuPanel() -> NSView {
    let width = computeMenuWidth()
    var rows: [NSView] = [
        HistoryHeaderItemView(text: "Select the clip you want to add to your clipboard", width: width),
        HistoryMenuItemView(
            text: "Thanks for the quick reply, I'll pass it to the team. → Дякую за швидку відповідь, передам команді.",
            shortcut: "⌘1", width: width),
        HistoryMenuItemView(
            text: "the app works great and is very usefull → The app works great and is very useful",
            shortcut: "⌘2", width: width),
        HistoryMenuItemView(
            text: "Bonjour, comment allez-vous aujourd'hui? → Hello, how are you today?",
            shortcut: "⌘3", width: width),
        MenuSeparatorView(width: width),
        OperationMenuRowView(title: "Translate", symbol: "globe", shortcut: "⌥T", width: width),
        OperationMenuRowView(title: "Fix grammar", symbol: "checkmark.seal", shortcut: "", width: width),
        OperationMenuRowView(title: "Rewrite", symbol: "wand.and.stars", shortcut: "", width: width),
        OperationMenuRowView(title: "Explain", symbol: "text.magnifyingglass", shortcut: "", width: width),
        OperationMenuRowView(title: "Screen Translate", symbol: "camera.viewfinder", shortcut: "", width: width),
        OperationMenuRowView(title: "Magic", symbol: "sparkles", shortcut: "", width: width),
        MenuSeparatorView(width: width),
        SubmenuRowView(title: "Target: \(AppFixture.targetLanguage)", width: width),
        CommandRowView(title: "History…", shortcut: "⌘H", width: width),
        CommandRowView(title: "Settings…", shortcut: "\u{2318},", width: width),
        MenuSeparatorView(width: width),
        CommandRowView(title: "Quit LingoPop", shortcut: "⌘Q", width: width)
    ]
    let totalH = rows.reduce(0) { $0 + $1.frame.height } + 8
    let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: totalH))
    effect.material = .menu
    effect.blendingMode = .behindWindow
    effect.state = .active
    effect.wantsLayer = true
    effect.layer?.cornerRadius = 6
    effect.layer?.masksToBounds = true
    var y = totalH - 4
    for row in rows {
        y -= row.frame.height
        row.frame.origin = NSPoint(x: 0, y: y)
        effect.addSubview(row)
    }
    return effect
}

// MARK: - SwiftUI fixture views

struct FixtureResultPopup: View {
    private let headerSize: CGFloat = 11
    private var popupWidth: CGFloat {
        min(700, max(480, 200 + CGFloat(AppFixture.translated.count) * 8.0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 28, height: 3)
                Spacer()
            }
            .frame(height: 8).padding(.bottom, 2)

            HStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: headerSize, weight: .semibold))
                Text("Claude →").font(.system(size: headerSize, weight: .semibold))
                HStack(spacing: 2) {
                    Text(AppFixture.targetLanguage).font(.system(size: headerSize, weight: .semibold))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(.secondary)

            Text(AppFixture.translated)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)

            HStack(spacing: 8) {
                Button {} label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button {} label: { Label("Replace", systemImage: "arrow.uturn.left") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button {} label: { Label("Rewrite", systemImage: "wand.and.stars") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button {} label: { Label("Explain", systemImage: "text.magnifyingglass") }
                    .buttonStyle(.bordered).controlSize(.small)
                Spacer(minLength: 0)
                Button {} label: { Label("Retry", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: popupWidth, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

struct FixtureOCRPopup: View {
    private let headerSize: CGFloat = 11

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 28, height: 3)
                Spacer()
            }
            .frame(height: 8).padding(.bottom, 2)

            HStack(spacing: 4) {
                Image(systemName: "text.viewfinder").font(.system(size: headerSize, weight: .semibold))
                Text("Recognized text").font(.system(size: headerSize, weight: .semibold))
            }
            .foregroundStyle(.secondary)

            Text(AppFixture.ocrText)
                .font(.system(size: 13))
                .padding(.vertical, 8)

            HStack(spacing: 8) {
                Button {} label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.bordered).controlSize(.small)
                Button {} label: { Label("Translate", systemImage: "globe") }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Spacer(minLength: 0)
                Button {} label: { Label("Retry", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 380, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

struct FixtureSettingsShell<Content: View>: View {
    let selectedTab: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        TabView(selection: .constant(selectedTab)) {
            content().tag(0).tabItem { Label("Main", systemImage: "slider.horizontal.3") }
            Color.clear.tag(1).tabItem { Label("Providers", systemImage: "cpu") }
            Color.clear.tag(2).tabItem { Label("Shortcuts", systemImage: "command") }
            Color.clear.tag(3).tabItem { Label("Usage", systemImage: "chart.bar.xaxis") }
            Color.clear.tag(4).tabItem { Label("Magic", systemImage: "sparkles") }
            Color.clear.tag(5).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 720, height: 560)
    }
}

struct FixtureMainTab: View {
    var body: some View {
        Form {
            Section("Target language") {
                Toggle("Auto-detect input language", isOn: .constant(false))
                Picker("Target", selection: .constant(AppFixture.targetLanguage)) {
                    Text(AppFixture.targetLanguage).tag(AppFixture.targetLanguage)
                }
            }
            Section("Popup") {
                LabeledContent("Result font size") {
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                        Slider(value: .constant(13), in: 11...20, step: 1).frame(width: 160)
                        Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                        Text("13 pt").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Limits") {
                LabeledContent("Max input characters") {
                    Text("5000").multilineTextAlignment(.trailing)
                }
                LabeledContent("History size") {
                    Text("10")
                }
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: .constant(false))
            }
            Section("iCloud Drive sync") {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.fill").foregroundStyle(.blue)
                    Text("iCloud Drive available").font(.system(size: 12))
                    Spacer()
                }
                Toggle("Sync settings & history via iCloud Drive", isOn: .constant(true))
            }
            Section("Accessibility") {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Granted").font(.system(size: 12))
                    Spacer()
                    Button("Re-check") {}
                }
            }
            Section("Screen Recording") {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    Text("Granted").font(.system(size: 12))
                    Spacer()
                    Button("Re-check") {}
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct FixtureProvidersTab: View {
    private let providers: [(name: String, badge: String, active: Bool)] = [
        ("Claude", "Key set", true),
        ("OpenAI", "No key", false),
        ("Gemini", "No key", false),
        ("Google (Free)", "No key needed", false),
        ("Google Translate", "No key", false),
        ("DeepL", "No key", false),
        ("Microsoft Translator", "No key", false)
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(providers.indices, id: \.self) { i in
                    let p = providers[i]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(p.name).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(p.active ? Color.accentColor : Color.primary)
                            if p.active {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text(p.badge)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(p.active ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 220)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            Form {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "cpu").font(.system(size: 24)).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Claude").font(.system(size: 16, weight: .semibold))
                            Text("Translate · Fix grammar · Rewrite · Explain · Screen Translate · Magic")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("Active", systemImage: "star.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(.yellow)
                    }
                }
                Section("API key") {
                    Label("A key is stored", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    SecureField("Enter a new key to replace", text: .constant(""))
                }
                Section("Endpoint") {
                    TextField("Base URL", text: .constant(AppFixture.claudeBaseURL))
                    Text("Default: \(AppFixture.claudeBaseURL)").font(.caption).foregroundStyle(.secondary)
                }
                Section("Model") {
                    TextField("Model name", text: .constant(AppFixture.claudeModel))
                }
                Section("Fallback") {
                    LabeledContent("If Claude fails") {
                        Picker("", selection: .constant("none")) {
                            Text("Don't fall back").tag("none")
                        }
                        .labelsHidden()
                    }
                }
                Section {
                    HStack {
                        Spacer()
                        Button("Save") {}.buttonStyle(.borderedProminent)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct FixtureShortcutsTab: View {
    let ops: [(String, String, String?)] = [
        ("globe", "Translate", "⌥T"),
        ("checkmark.seal", "Fix grammar", nil),
        ("wand.and.stars", "Rewrite", nil),
        ("text.magnifyingglass", "Explain", nil),
        ("camera.viewfinder", "Screen Translate", nil),
        ("sparkles", "Magic", nil)
    ]

    var body: some View {
        Form {
            Section("Shortcuts") {
                ForEach(ops, id: \.1) { sym, name, hk in
                    LabeledContent {
                        Text(hk ?? "Not set")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(hk == nil ? .secondary : .primary)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.12)))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: sym).foregroundStyle(.secondary)
                            Text(name)
                        }
                    }
                }
            }
            Section {
                Text("Click a shortcut field, then press a key combination. Use any of ⌃ ⌥ ⇧ ⌘ plus a key. Esc cancels recording. ✕ removes the shortcut.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct FixtureAboutTab: View {
    private var iconImage: NSImage {
        var url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let iconPath = url.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png")
        if let img = NSImage(contentsOf: iconPath) { return img }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: iconImage).resizable().scaledToFit().frame(width: 120, height: 120).padding(.top, 16)
            Text("LingoPop").font(.system(size: 26, weight: .semibold))
            Text("Version \(AppFixture.version)").font(.caption).foregroundStyle(.secondary)
            Divider().padding(.vertical, 6)
            Text("Select text anywhere on your Mac, press a shortcut, and get an instant AI translation, grammar fix, or rewrite in a popup near your cursor.")
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Text("Supports Claude, OpenAI, Gemini, and Google Translate. API keys are stored locally in an encrypted file. Settings sync between Macs via iCloud Drive.")
                .font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            Link("Privacy Policy", destination: URL(string: "https://github.com/slucheninov/lingopop/blob/main/PRIVACY.md")!)
                .font(.system(size: 12))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}


struct FixtureMagicTab: View {
    private let prompt = "You are a professional writing assistant. Fix all grammar, spelling, and punctuation errors, improve clarity, flow, and style, and if the text is not in {{targetLanguage}}, translate it into {{targetLanguage}}. Return only the result - no explanations, no notes."
    private var charCount: Int { prompt.unicodeScalars.count }
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Magic runs a single AI call with your custom system prompt. Use {{targetLanguage}} to insert your configured target language automatically.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    TextEditor(text: .constant(prompt))
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                    HStack {
                        Text("\(charCount) / 2000")
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                        Spacer()
                        Button("Reset to default") {}
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                        Button("Save") {}
                            .buttonStyle(.borderedProminent)
                            .disabled(true)
                    }
                }
            } header: {
                Text("System prompt")
            }
        }
        .formStyle(.grouped)
    }
}

struct FixtureHistoryView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history", text: .constant(""))
                    .textFieldStyle(.plain)
                Spacer()
                Button {} label: {
                    Label("Clear", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .padding(10)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    historyRow(
                        symbol: "globe", op: "Translation", langBadge: "Russian → English",
                        orig: "Выберите текст в любом месте на вашем Mac",
                        trans: "Select text anywhere on your Mac",
                        time: "Jun 9, 2026, 3:15 PM"
                    )
                    Divider().padding(.horizontal, 8)
                    historyRow(
                        symbol: "checkmark.seal", op: "Grammar fix", langBadge: nil,
                        orig: "the app works great and is very usefull",
                        trans: "The app works great and is very useful",
                        time: "Jun 9, 2026, 2:50 PM"
                    )
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func historyRow(
        symbol: String, op: String, langBadge: String?,
        orig: String, trans: String, time: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(op, systemImage: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let langBadge {
                    badge(langBadge)
                }
                badge("Claude")
                Spacer()
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Menu {
                    Button("Copy original") {}
                    Button("Copy translation") {}
                    Divider()
                    Button("Delete", role: .destructive) {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            Text(orig)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(trans)
                .font(.system(size: 13))
                .lineLimit(6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
    }
}

struct SettingsTabBar: View {
    let selected: Int
    private let tabs: [(String, String)] = [
        ("Main", "slider.horizontal.3"),
        ("Providers", "cpu"),
        ("Shortcuts", "command"),
        ("Usage", "chart.bar.xaxis"),
        ("Magic", "sparkles"),
        ("About", "info.circle")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs.indices, id: \.self) { i in
                let (name, sym) = tabs[i]
                VStack(spacing: 3) {
                    Image(systemName: sym).font(.system(size: 13, weight: .medium))
                    Text(name).font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(i == selected ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(i == selected ? Color.accentColor.opacity(0.12) : Color.clear)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5)
        }
    }
}

struct SettingsTabHost: View {
    let tab: Int
    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selected: tab)
            Group {
                switch tab {
                case 0: FixtureMainTab()
                case 1: FixtureProvidersTab()
                case 2: FixtureShortcutsTab()
                case 4: FixtureMagicTab()
                case 5: FixtureAboutTab()
                default: Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Render all

func renderAll(outDir: String) throws {
    NSApp.appearance = NSAppearance(named: .aqua)
    let fm = FileManager.default
    try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    let canvas = NSSize(width: 1200, height: 720)

    // Popup
    let popup = snapshotSwiftUI(FixtureResultPopup())
    try savePNG(compositeOnDesktop(content: popup, canvasSize: canvas,
        caption: "Translate · Fix grammar · Rewrite — wherever your cursor is."), to: "\(outDir)/popup.png")
    print("Wrote \(outDir)/popup.png")

    // Menu
    let menuPanel = buildMenuPanel()
    let menuImg = snapshotView(menuPanel)
    try savePNG(compositeOnDesktop(content: menuImg, canvasSize: canvas,
        caption: "Seven providers · iCloud-synced settings · Screen Translate"), to: "\(outDir)/menu.png")
    print("Wrote \(outDir)/menu.png")

    // Popup screen
    let ocr = snapshotSwiftUI(FixtureOCRPopup())
    try savePNG(compositeOnDesktop(content: ocr, canvasSize: canvas,
        caption: "Screen Translate — capture any region, OCR + translate in one step."), to: "\(outDir)/popup-screen.png")
    print("Wrote \(outDir)/popup-screen.png")

    // Settings + History — window chrome on gradient desktop (same canvas as menu/popup)
    for (tab, name) in [(0, "settings-main"), (1, "settings-providers"), (2, "settings-shortcuts"), (4, "settings-magic"), (5, "settings-about")] {
        let img = snapshotChromeWindow(title: "LingoPop Settings", width: 720, contentHeight: 560) {
            SettingsTabHost(tab: tab)
        }
        try savePNG(compositeOnDesktop(content: img, canvasSize: canvas), to: "\(outDir)/\(name).png")
        print("Wrote \(outDir)/\(name).png")
    }

    let hist = snapshotChromeWindow(title: "Translation History", width: 540, contentHeight: 480) {
        FixtureHistoryView()
    }
    try savePNG(compositeOnDesktop(content: hist, canvasSize: canvas), to: "\(outDir)/history.png")
    print("Wrote \(outDir)/history.png")
}

// MARK: - Entry

@main
enum ScreenshotRenderer {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        do {
            try renderAll(outDir: outDir)
        } catch {
            fputs("Error: \(error)\n", stderr)
            exit(1)
        }
    }
}

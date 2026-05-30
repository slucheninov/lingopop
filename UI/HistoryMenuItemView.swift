import AppKit

enum StatusMenuMetrics {
    static let horizontalInset: CGFloat = 14
    static let iconSize: CGFloat = 16
    static let iconTitleGap: CGFloat = 8
    static let titleShortcutGap: CGFloat = 19
    static let rowHeight: CGFloat = 22
    static let headerHeight: CGFloat = 28
    static let highlightHorizontalInset: CGFloat = 5
    static let highlightCornerRadius: CGFloat = 5

    static var titleLeading: CGFloat { horizontalInset + iconSize + iconTitleGap }
}

/// Non-interactive header row shown above the clipboard-style history list,
/// with a hairline separator along its bottom edge.
final class HistoryHeaderItemView: NSView {

    private let label = NSTextField(labelWithString: "")

    init(text: String, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: StatusMenuMetrics.headerHeight))

        label.stringValue = text
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: StatusMenuMetrics.headerHeight),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: StatusMenuMetrics.horizontalInset),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -StatusMenuMetrics.horizontalInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -1)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let y = bounds.minY + 0.5
        let path = NSBezierPath()
        path.move(to: NSPoint(x: StatusMenuMetrics.horizontalInset, y: y))
        path.line(to: NSPoint(x: bounds.maxX - StatusMenuMetrics.horizontalInset, y: y))
        path.lineWidth = 1
        path.stroke()
    }
}

final class HistoryMenuItemView: NSView {

    private let horizontalInset: CGFloat
    private let label = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let selectionView = NSVisualEffectView()

    private(set) var isHighlighted = false {
        didSet {
            guard isHighlighted != oldValue else { return }
            selectionView.isHidden = !isHighlighted
            label.textColor = isHighlighted ? .selectedMenuItemTextColor : .labelColor
            shortcutLabel.textColor = isHighlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
        }
    }

    init(
        text: String,
        shortcut: String,
        width: CGFloat,
        horizontalInset: CGFloat = StatusMenuMetrics.horizontalInset
    ) {
        self.horizontalInset = horizontalInset
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: StatusMenuMetrics.rowHeight))

        let font = NSFont.menuFont(ofSize: 0)

        shortcutLabel.stringValue = shortcut
        shortcutLabel.font = font
        shortcutLabel.textColor = .tertiaryLabelColor
        shortcutLabel.alignment = .right
        configureLabel(shortcutLabel)
        let shortcutWidth = shortcut.isEmpty
            ? 0
            : (shortcut as NSString).size(withAttributes: [.font: font]).width + StatusMenuMetrics.titleShortcutGap

        let textWidth = width - horizontalInset * 2 - shortcutWidth
        label.stringValue = Self.truncated(text, maxWidth: textWidth, font: font)
        label.font = font
        configureLabel(label)

        selectionView.material = .selection
        selectionView.state = .active
        selectionView.isEmphasized = true
        selectionView.blendingMode = .behindWindow
        selectionView.maskImage = Self.roundedMaskImage(cornerRadius: StatusMenuMetrics.highlightCornerRadius)
        selectionView.isHidden = true
        selectionView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(selectionView)
        addSubview(label)
        addSubview(shortcutLabel)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: StatusMenuMetrics.rowHeight),
            selectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: StatusMenuMetrics.highlightHorizontalInset),
            selectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -StatusMenuMetrics.highlightHorizontalInset),
            selectionView.topAnchor.constraint(equalTo: topAnchor),
            selectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalInset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalInset),
            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            shortcutLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureLabel(_ field: NSTextField) {
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.backgroundColor = .clear
        field.isBordered = false
        field.isEditable = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setContentHuggingPriority(.required, for: .horizontal)
    }

    func setHighlighted(_ highlighted: Bool) {
        isHighlighted = highlighted
    }

    private static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let length = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: length, height: length), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }

    private static func truncated(_ text: String, maxWidth: CGFloat, font: NSFont) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        guard (text as NSString).size(withAttributes: attrs).width > maxWidth else { return text }
        let chars = Array(text)
        var lo = 0, hi = chars.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = String(chars.prefix(mid)) + "…"
            if (candidate as NSString).size(withAttributes: attrs).width <= maxWidth {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo == 0 ? "…" : String(chars.prefix(lo)) + "…"
    }
}

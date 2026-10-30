import AppKit

/// How the popup's action row renders its buttons. The first `labelledPrefix` buttons of
/// the row (Copy + the next one: Replace, Rewrite or Translate) keep their text labels in
/// every mode except `.compact`; the Retry menu and every other button follow the mode.
enum ActionRowMode: Equatable {
    /// Every button shows its text label.
    case full
    /// The first two buttons keep their labels, the rest are icon-only.
    case mixed
    /// Last-resort fallback when even `.mixed` does not fit: icons only.
    case compact

    /// Number of leading buttons that stay labelled (as long as they fit).
    static let labelledPrefix = 2

    /// Whether the button at `index` (0-based, in row order, Retry menu last) is icon-only.
    func isIconOnly(at index: Int) -> Bool {
        switch self {
        case .full: return false
        case .mixed: return index >= Self.labelledPrefix
        case .compact: return true
        }
    }

    /// The mode to try first. Text of at least `threshold` characters counts as long and
    /// prefers `.full`; shorter text prefers `.mixed`. With no button beyond the labelled
    /// prefix (`buttonCount <= labelledPrefix`) `.mixed` and `.full` are the same row, so
    /// `.full` is returned.
    static func preferred(characterCount: Int, threshold: Int, buttonCount: Int) -> ActionRowMode {
        if buttonCount <= labelledPrefix { return .full }
        return characterCount >= threshold ? .full : .mixed
    }

    /// Fallback chain, widest first: what `ViewThatFits` should offer in order.
    var candidates: [ActionRowMode] {
        switch self {
        case .full: return [.full, .mixed, .compact]
        case .mixed: return [.mixed, .compact]
        case .compact: return [.compact]
        }
    }
}

/// Pure width math for the popup's action button row, so the popup can grow to fit
/// long localized titles (and tests can pin the numbers).
enum ActionRowMetrics {
    private static let buttonFontSize: CGFloat = 11
    /// Icon + icon/label gap + horizontal bezel padding of a small bordered button.
    private static let buttonChrome: CGFloat = 38
    /// Extra width of the Retry menu's disclosure chevron.
    private static let menuIndicatorWidth: CGFloat = 14
    /// Icon-only small bordered button: glyph plus bezel padding.
    private static let iconButtonWidth: CGFloat = 30
    private static let buttonSpacing: CGFloat = 8
    /// Chevron-only menu button (e.g. the OCR "Translate with..." menu): 14 pt glyph frame
    /// plus bordered bezel padding, and the 4 pt gap to the button it is attached to.
    private static let chevronMenuWidth: CGFloat = 14 + 16
    private static let attachedSpacing: CGFloat = 4
    private static let rowInset: CGFloat = 28 // 2 x PopupLayout.contentPadding

    static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: buttonFontSize)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Width needed to show the row in `mode` (default: every button with its full title).
    /// `titles` are the plain buttons in row order; `menuTitle` is the Retry menu, if shown
    /// (it sits after the plain buttons); `chevronMenus` counts chevron-only menus attached
    /// to the last plain button.
    static func width(titles: [String], menuTitle: String?, chevronMenus: Int = 0,
                      mode: ActionRowMode = .full) -> CGFloat {
        var widths = titles.enumerated().map { index, title in
            mode.isIconOnly(at: index) ? iconButtonWidth : textWidth(title) + buttonChrome
        }
        if chevronMenus > 0, !widths.isEmpty {
            widths[widths.count - 1] += CGFloat(chevronMenus) * (chevronMenuWidth + attachedSpacing)
        }
        if let menuTitle {
            let base = mode.isIconOnly(at: titles.count) ? iconButtonWidth : textWidth(menuTitle) + buttonChrome
            widths.append(base + menuIndicatorWidth)
        }
        guard !widths.isEmpty else { return 0 }
        // The rows put a `Spacer` before Retry, and the HStack spaces it like any other
        // child, so there is one gap more than between the buttons alone.
        return widths.reduce(0, +) + buttonSpacing * CGFloat(widths.count) + rowInset
    }
}

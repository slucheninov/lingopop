import AppKit

/// Pure width math for the popup's action button row, so the popup can grow to fit
/// long localized titles (and tests can pin the numbers).
enum ActionRowMetrics {
    private static let buttonFontSize: CGFloat = 11
    /// Icon + icon/label gap + horizontal bezel padding of a small bordered button.
    private static let buttonChrome: CGFloat = 38
    /// Extra width of the Retry menu's disclosure chevron.
    private static let menuIndicatorWidth: CGFloat = 14
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

    /// Width needed to show every button with its full title in one row. `titles` are the
    /// plain buttons; `menuTitle` is the Retry menu, if shown; `chevronMenus` counts
    /// chevron-only menus attached to the last plain button.
    static func width(titles: [String], menuTitle: String?, chevronMenus: Int = 0) -> CGFloat {
        var widths = titles.map { textWidth($0) + buttonChrome }
        if chevronMenus > 0, !widths.isEmpty {
            widths[widths.count - 1] += CGFloat(chevronMenus) * (chevronMenuWidth + attachedSpacing)
        }
        if let menuTitle { widths.append(textWidth(menuTitle) + buttonChrome + menuIndicatorWidth) }
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + buttonSpacing * CGFloat(widths.count - 1) + rowInset
    }
}

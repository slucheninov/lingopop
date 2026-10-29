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
    private static let rowInset: CGFloat = 28 // 2 x PopupLayout.contentPadding

    static func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: buttonFontSize)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// Width needed to show every button with its full title in one row. `titles` are the
    /// plain buttons; `menuTitle` is the Retry menu, if shown.
    static func width(titles: [String], menuTitle: String?) -> CGFloat {
        var widths = titles.map { textWidth($0) + buttonChrome }
        if let menuTitle { widths.append(textWidth(menuTitle) + buttonChrome + menuIndicatorWidth) }
        guard !widths.isEmpty else { return 0 }
        return widths.reduce(0, +) + buttonSpacing * CGFloat(widths.count - 1) + rowInset
    }
}

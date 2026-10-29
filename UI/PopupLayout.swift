import SwiftUI

/// Geometry, timing and font-derived metrics shared by the popup window, view and state.
struct PopupLayout {

    // MARK: Panel geometry

    /// Initial panel width; the real size follows the SwiftUI content.
    static let panelWidth: CGFloat = 360
    static let minPanelHeight: CGFloat = 100
    /// Height assumed when the content view cannot report a fitting size.
    static let fallbackPanelHeight: CGFloat = 120
    /// Gap between the cursor and the panel.
    static let cursorOffset: CGFloat = 12
    /// Minimum gap between the panel and the screen edge.
    static let screenEdgeInset: CGFloat = 8

    // MARK: Fades

    static let fadeInDuration: TimeInterval = 0.18
    static let fadeOutDuration: TimeInterval = 0.15

    // MARK: Content

    static let contentPadding: CGFloat = 14
    static let stackSpacing: CGFloat = 8
    static let cornerRadius: CGFloat = 12
    /// Characters of the original text shown in the loading preview.
    static let previewCharacterLimit = 120
    /// Hover delay before the custom button tooltip appears (500 ms).
    static let tooltipDelayNanoseconds: UInt64 = 500_000_000

    // MARK: Dynamic width

    static let minWidthFloor: CGFloat = 320
    static let maxWidth: CGFloat = 700
    private static let headerWidthFactor: CGFloat = 30
    private static let widthBase: CGFloat = 200
    private static let referenceFontSize: CGFloat = 13

    // MARK: Font-derived metrics

    let fontSize: Double

    init(fontSize: Double = PopupPrefs.defaultFontSize) {
        self.fontSize = fontSize
    }

    var headerFontSize: CGFloat { max(8, CGFloat(fontSize) - 2) }

    /// Content-dependent popup width: grows with the amount of text, clamped to
    /// `minWidthFloor...maxWidth` (the lower bound also scales with the header font).
    func dynamicWidth(for phase: PopupState.Phase) -> CGFloat {
        let minW = max(Self.minWidthFloor, headerFontSize * Self.headerWidthFactor)
        let text: String
        switch phase {
        case .result(let result): text = result.translated
        case .ocr(let t): text = t
        default: return minW
        }
        let chars = CGFloat(text.count)
        let fontFactor = CGFloat(fontSize) / Self.referenceFontSize
        return min(Self.maxWidth, max(minW, Self.widthBase + chars * fontFactor))
    }
}

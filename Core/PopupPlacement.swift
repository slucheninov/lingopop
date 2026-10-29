import CoreGraphics

/// Pure placement math for the popup (AppKit coordinates, Y up), kept free of AppKit
/// so it can be unit-tested.
enum PopupPlacement {

    /// Frame for a popup of `size` shown near `anchor`, kept inside `visibleFrame`
    /// shrunk by `inset`. Prefers below-right of the anchor, flips above when it does
    /// not fit below, and otherwise clamps on the side with more room.
    static func frame(size: CGSize, anchor: CGPoint, visibleFrame: CGRect,
                      offset: CGFloat, inset: CGFloat) -> CGRect {
        let bounds = visibleFrame.insetBy(dx: inset, dy: inset)
        let x = anchor.x + offset

        let belowY = anchor.y - offset - size.height
        let aboveY = anchor.y + offset
        let y: CGFloat
        if belowY >= bounds.minY {
            y = belowY
        } else if aboveY + size.height <= bounds.maxY {
            y = aboveY
        } else {
            let roomBelow = anchor.y - offset - bounds.minY
            let roomAbove = bounds.maxY - aboveY
            y = roomBelow >= roomAbove ? belowY : aboveY
        }
        return clamp(CGRect(x: x, y: y, width: size.width, height: size.height), into: bounds)
    }

    /// Moves `rect` the minimum distance to lie inside `bounds`; when it is taller
    /// (wider) than `bounds` the top (left) edge is pinned.
    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var origin = rect.origin
        origin.x = min(origin.x, bounds.maxX - rect.width)
        origin.x = max(origin.x, bounds.minX)
        origin.y = max(origin.y, bounds.minY)
        origin.y = min(origin.y, bounds.maxY - rect.height)
        if rect.height > bounds.height { origin.y = bounds.maxY - rect.height }
        return CGRect(origin: origin, size: rect.size)
    }
}

import XCTest

final class PopupPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 100, width: 1000, height: 800) // Dock below: minY 100
    private let size = CGSize(width: 300, height: 200)
    private let offset: CGFloat = 12
    private let inset: CGFloat = 8

    private func place(_ size: CGSize, _ anchor: CGPoint, in screen: CGRect? = nil) -> CGRect {
        PopupPlacement.frame(size: size, anchor: anchor, visibleFrame: screen ?? self.screen,
                             offset: offset, inset: inset)
    }

    private func assertInside(_ r: CGRect, _ s: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        let b = s.insetBy(dx: inset, dy: inset)
        XCTAssertTrue(b.contains(r), "\(r) not inside \(b)", file: file, line: line)
    }

    func test_normal_placesBelowRightOfAnchor() {
        let r = place(size, CGPoint(x: 400, y: 600))
        XCTAssertEqual(r.minX, 412)
        XCTAssertEqual(r.maxY, 588)
    }

    func test_rightEdge_shiftsLeft() {
        let r = place(size, CGPoint(x: 950, y: 600))
        XCTAssertEqual(r.maxX, 1000 - inset)
        assertInside(r, screen)
    }

    func test_leftEdge_neverBelowMinXPlusInset() {
        let r = place(size, CGPoint(x: -50, y: 600), in: screen)
        XCTAssertEqual(r.minX, inset)
    }

    func test_bottomEdge_flipsAboveAnchor() {
        let r = place(size, CGPoint(x: 400, y: 150))
        XCTAssertEqual(r.minY, 162)
        assertInside(r, screen)
    }

    func test_nearBottomTallContent_clampedInside() {
        // Fits neither below (room 38) nor above-clear of the top edge: 700 tall in 784 usable.
        let tall = CGSize(width: 300, height: 700)
        let r = place(tall, CGPoint(x: 400, y: 300))
        assertInside(r, screen)
    }

    func test_contentTallerThanScreen_pinsTop() {
        let huge = CGSize(width: 300, height: 2000)
        let r = place(huge, CGPoint(x: 400, y: 500))
        XCTAssertEqual(r.maxY, screen.maxY - inset)
    }

    func test_multiMonitor_negativeOrigin() {
        let left = CGRect(x: -1920, y: -200, width: 1920, height: 1000)
        let r = place(size, CGPoint(x: -30, y: -150), in: left)
        assertInside(r, left)
        XCTAssertEqual(r.minY, -138) // flipped above the anchor
        XCTAssertEqual(r.maxX, -inset) // shifted left off the right edge
    }

    func test_clamp_pullsDraggedFrameBackInside() {
        let b = screen.insetBy(dx: inset, dy: inset)
        let r = PopupPlacement.clamp(CGRect(x: 900, y: 50, width: 300, height: 200), into: b)
        assertInside(r, screen)
    }
}

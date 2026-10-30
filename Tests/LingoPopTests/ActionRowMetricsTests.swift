import XCTest

final class ActionRowMetricsTests: XCTestCase {
    private let maxPanelWidth: CGFloat = 700

    func test_longerTitlesNeedMoreWidth() {
        let en = ActionRowMetrics.width(titles: ["Copy", "Replace", "Rewrite", "Explain"], menuTitle: "Retry")
        let uk = ActionRowMetrics.width(titles: ["Копіювати", "Замінити", "Переписати", "Пояснити"], menuTitle: "Спробувати ще раз")
        XCTAssertGreaterThan(uk, en)
        XCTAssertGreaterThan(uk, 320, "Ukrainian row does not fit the minimum popup width")
    }

    func test_shippedLanguagesFitWithinMaxWidth() {
        let rows: [[String]] = [
            ["Kopiuj", "Zamień", "Przepisz", "Wyjaśnij", "Ponów próbę"],
            ["Копіювати", "Замінити", "Переписати", "Пояснити", "Спробувати ще раз"],
            ["Kopieren", "Ersetzen", "Umschreiben", "Erklären", "Wiederholen"],
        ]
        for row in rows {
            let w = ActionRowMetrics.width(titles: Array(row.dropLast()), menuTitle: row.last)
            XCTAssertLessThan(w, maxPanelWidth, "\(row)")
        }
    }

    func test_chevronMenuWidensRow() {
        let titles = ["Copy", "Translate"]
        let without = ActionRowMetrics.width(titles: titles, menuTitle: "Retry")
        let with = ActionRowMetrics.width(titles: titles, menuTitle: "Retry", chevronMenus: 1)
        XCTAssertGreaterThan(with, without)
    }

    func test_emptyRowIsZero() {
        XCTAssertEqual(ActionRowMetrics.width(titles: [], menuTitle: nil), 0)
    }

    // MARK: - Modes

    private let shippedTitles: [(titles: [String], retry: String)] = [
        (["Copy", "Replace", "Rewrite", "Explain"], "Retry"),
        (["Kopiuj", "Zamień", "Przepisz", "Wyjaśnij"], "Ponów próbę"),
        (["Копіювати", "Замінити", "Переписати", "Пояснити"], "Спробувати ще раз"),
        (["Kopieren", "Ersetzen", "Umschreiben", "Erklären"], "Wiederholen"),
    ]

    func test_widthShrinksFromFullToMixedToCompact() {
        for row in shippedTitles {
            let full = ActionRowMetrics.width(titles: row.titles, menuTitle: row.retry, mode: .full)
            let mixed = ActionRowMetrics.width(titles: row.titles, menuTitle: row.retry, mode: .mixed)
            let compact = ActionRowMetrics.width(titles: row.titles, menuTitle: row.retry, mode: .compact)
            XCTAssertLessThan(mixed, full, "\(row)")
            XCTAssertLessThan(compact, mixed, "\(row)")
        }
    }

    func test_defaultModeIsFull() {
        let row = shippedTitles[0]
        XCTAssertEqual(
            ActionRowMetrics.width(titles: row.titles, menuTitle: row.retry),
            ActionRowMetrics.width(titles: row.titles, menuTitle: row.retry, mode: .full)
        )
    }

    func test_mixedWidthUsesLabelsOnlyForFirstTwoButtons() {
        // Changing a title beyond the first two must not change the mixed width.
        let a = ActionRowMetrics.width(titles: ["Copy", "Replace", "Rewrite", "Explain"], menuTitle: "Retry", mode: .mixed)
        let b = ActionRowMetrics.width(titles: ["Copy", "Replace", "A much longer rewrite", "Explain everything"], menuTitle: "Retry again later", mode: .mixed)
        XCTAssertEqual(a, b)
        // Changing the second title does change it.
        let c = ActionRowMetrics.width(titles: ["Copy", "Replace it all", "Rewrite", "Explain"], menuTitle: "Retry", mode: .mixed)
        XCTAssertGreaterThan(c, a)
    }

    func test_compactWidthIgnoresTitles() {
        let a = ActionRowMetrics.width(titles: ["a", "b", "c"], menuTitle: "x", mode: .compact)
        let b = ActionRowMetrics.width(titles: ["long title", "another long", "third long"], menuTitle: "retry long", mode: .compact)
        XCTAssertEqual(a, b)
    }

    func test_mixedEqualsFullWhenOnlyTheLabelledPrefixExists() {
        let titles = ["Copy", "Translate"]
        XCTAssertEqual(
            ActionRowMetrics.width(titles: titles, menuTitle: nil, chevronMenus: 1, mode: .mixed),
            ActionRowMetrics.width(titles: titles, menuTitle: nil, chevronMenus: 1, mode: .full)
        )
    }

    func test_mixedOcrRowKeepsChevronAndIconRetry() {
        let titles = ["Copy", "Translate"]
        let mixed = ActionRowMetrics.width(titles: titles, menuTitle: "Retry", chevronMenus: 1, mode: .mixed)
        let full = ActionRowMetrics.width(titles: titles, menuTitle: "Retry", chevronMenus: 1, mode: .full)
        let noChevron = ActionRowMetrics.width(titles: titles, menuTitle: "Retry", mode: .mixed)
        XCTAssertLessThan(mixed, full)
        XCTAssertGreaterThan(mixed, noChevron)
    }

    func test_iconOnlyIndexRules() {
        XCTAssertFalse(ActionRowMode.full.isIconOnly(at: 0))
        XCTAssertFalse(ActionRowMode.full.isIconOnly(at: 5))
        XCTAssertFalse(ActionRowMode.mixed.isIconOnly(at: 0))
        XCTAssertFalse(ActionRowMode.mixed.isIconOnly(at: 1))
        XCTAssertTrue(ActionRowMode.mixed.isIconOnly(at: 2))
        XCTAssertTrue(ActionRowMode.mixed.isIconOnly(at: 5))
        XCTAssertTrue(ActionRowMode.compact.isIconOnly(at: 0))
    }

    func test_preferredModeFollowsTextLengthThreshold() {
        XCTAssertEqual(ActionRowMode.preferred(characterCount: 0, threshold: 120, buttonCount: 5), .mixed)
        XCTAssertEqual(ActionRowMode.preferred(characterCount: 119, threshold: 120, buttonCount: 5), .mixed)
        XCTAssertEqual(ActionRowMode.preferred(characterCount: 120, threshold: 120, buttonCount: 5), .full)
        XCTAssertEqual(ActionRowMode.preferred(characterCount: 5000, threshold: 120, buttonCount: 3), .full)
    }

    func test_preferredModeIsFullWhenNoButtonBeyondThePrefix() {
        XCTAssertEqual(ActionRowMode.preferred(characterCount: 10, threshold: 120, buttonCount: 2), .full)
        XCTAssertEqual(ActionRowMode.preferred(characterCount: 10, threshold: 120, buttonCount: 1), .full)
    }

    func test_fallbackChains() {
        XCTAssertEqual(ActionRowMode.full.candidates, [.full, .mixed, .compact])
        XCTAssertEqual(ActionRowMode.mixed.candidates, [.mixed, .compact])
        XCTAssertEqual(ActionRowMode.compact.candidates, [.compact])
    }

    func test_shippedLanguagesMixedRowFitsMinimumPanel() {
        for row in shippedTitles {
            let w = ActionRowMetrics.width(titles: row.titles, menuTitle: row.retry, mode: .mixed)
            XCTAssertLessThan(w, maxPanelWidth, "\(row)")
        }
    }
}

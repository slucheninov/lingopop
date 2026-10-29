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

    func test_emptyRowIsZero() {
        XCTAssertEqual(ActionRowMetrics.width(titles: [], menuTitle: nil), 0)
    }
}

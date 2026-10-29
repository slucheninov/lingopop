import AppKit

/// What the status-bar menu asks of the app. Implemented by `AppDelegate`.
@MainActor
protocol StatusMenuActions: AnyObject {
    func statusMenuDidSelect(operation: AIOperation)
    func statusMenuDidRequestSettings()
    func statusMenuDidRequestAbout()
    func statusMenuDidRequestHistory()
}

/// Builds and refreshes the menu-bar item's menu (recent history, operations, target
/// language, Settings / History / Quit). It must be retained by its owner: menu items
/// reference it as their (weak) target and `NSMenu.delegate` is weak too.
/// User-visible menu strings, defined once so the menu and its width measurement agree.
private enum Strings {
    static let noRecent = String(localized: "No recent translations")
    static let historyHeader = String(localized: "Select the clip you want to add to your clipboard")
    static let history = String(localized: "History…")
    static let settings = String(localized: "Settings…")
    static let about = String(localized: "About LingoPop")
    static let quit = String(localized: "Quit LingoPop")
    static let recheckAccessibility = String(localized: "⚠ Re-check Accessibility…")

    /// `language` is the persisted English language name (data, never localized).
    static func target(_ language: String) -> String {
        String(localized: "Target: \(language)")
    }
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let settingsStore: SettingsStore
    private let historyStore: TranslationHistoryStore
    private weak var actions: StatusMenuActions?

    init(settingsStore: SettingsStore, historyStore: TranslationHistoryStore, actions: StatusMenuActions) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.actions = actions
        super.init()
    }

    /// Creates the (initially populated) menu with `self` as its delegate.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        rebuildMenu(menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for menuItem in menu.items {
            (menuItem.view as? HistoryMenuItemView)?.setHighlighted(menuItem == item)
        }
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let rowWidth = statusMenuRowWidth()
        let menuCount = min(settingsStore.menuHistoryCount, settingsStore.maxHistoryCount)
        let recentEntries = Array(historyStore.entries.prefix(menuCount))

        let header = NSMenuItem()
        header.view = HistoryHeaderItemView(
            text: Strings.historyHeader,
            width: rowWidth
        )
        header.isEnabled = false
        menu.addItem(header)

        if recentEntries.isEmpty {
            let placeholder = NSMenuItem()
            placeholder.view = HistoryHeaderItemView(
                text: Strings.noRecent,
                width: rowWidth,
                height: StatusMenuMetrics.rowHeight + 2,
                showsSeparator: false
            )
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        } else {
            for (index, entry) in recentEntries.enumerated() {
                let fullText = historyMenuText(entry)
                let item = NSMenuItem()
                let shortcutNumber = index < 10 ? String((index + 1) % 10) : ""
                item.view = HistoryMenuItemView(
                    text: fullText,
                    shortcut: shortcutNumber.isEmpty ? "" : "⌘\(shortcutNumber)",
                    width: rowWidth
                )
                if !shortcutNumber.isEmpty {
                    item.keyEquivalent = shortcutNumber
                    item.keyEquivalentModifierMask = .command
                }
                item.toolTip = fullText
                item.representedObject = entry.translated
                item.action = #selector(copyHistoryItemAction(_:))
                menu.addItem(item)
            }
        }
        menu.addItem(NSMenuItem.separator())

        for operation in AIOperation.allCases {
            let item = NSMenuItem(
                title: operation.displayName,
                action: #selector(operationMenuAction(_:)),
                keyEquivalent: ""
            )
            if let hk = settingsStore.hotkey(for: operation), !hk.isEmpty, let key = hk.hotKeyKey {
                // Named keys (Space, Return, F-keys, arrows) stringify to multi-character
                // names that are not valid key equivalents; only set single characters.
                let equivalent = String(describing: key).lowercased()
                if equivalent.count == 1 {
                    item.keyEquivalent = equivalent
                    item.keyEquivalentModifierMask = hk.modifiers
                }
            }
            item.representedObject = operation.rawValue
            item.image = NSImage(systemSymbolName: operation.systemImage, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeLanguageSubmenu())
        menu.addItem(NSMenuItem(title: Strings.history, action: #selector(historyAction), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: Strings.settings, action: #selector(settingsAction), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: Strings.about, action: #selector(aboutAction), keyEquivalent: ""))
        if !PermissionsManager.isAccessibilityGranted() {
            menu.addItem(NSMenuItem.separator())
            let item = NSMenuItem(title: Strings.recheckAccessibility, action: #selector(recheckAccessibilityAction), keyEquivalent: "")
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: Strings.quit, action: #selector(quitAction), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
    }

    private func makeLanguageSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: Strings.target(settingsStore.targetLanguage), action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: String(localized: "Target language"))
        var languages = Languages.quickList
        if !languages.contains(settingsStore.targetLanguage) {
            languages.insert(settingsStore.targetLanguage, at: 0)
        }
        for lang in languages {
            let item = NSMenuItem(title: lang, action: #selector(selectLanguageAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang
            item.state = (lang == settingsStore.targetLanguage) ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func operationMenuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let op = AIOperation(rawValue: raw) else { return }
        actions?.statusMenuDidSelect(operation: op)
    }

    @objc private func selectLanguageAction(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? String else { return }
        settingsStore.targetLanguage = lang
        settingsStore.save()
    }

    @objc private func settingsAction() {
        actions?.statusMenuDidRequestSettings()
    }

    @objc private func aboutAction() {
        actions?.statusMenuDidRequestAbout()
    }

    @objc private func historyAction() {
        actions?.statusMenuDidRequestHistory()
    }

    @objc private func copyHistoryItemAction(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func historyMenuText(_ entry: TranslationHistoryEntry) -> String {
        let original = entry.original.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        let translated = entry.translated.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return "\(original) → \(translated)"
    }


    private func statusMenuRowWidth() -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let iconAndGap = StatusMenuMetrics.iconSize + StatusMenuMetrics.iconTitleGap
        let shortcutGap = StatusMenuMetrics.titleShortcutGap
        let submenuChevron: CGFloat = 14
        let horizontalPadding = StatusMenuMetrics.horizontalInset * 2
        var maxContent: CGFloat = (Strings.historyHeader as NSString).size(withAttributes: attrs).width
        maxContent = max(maxContent, (Strings.noRecent as NSString).size(withAttributes: attrs).width)

        for operation in AIOperation.allCases {
            var row = iconAndGap + (operation.displayName as NSString).size(withAttributes: attrs).width
            if let hk = settingsStore.hotkey(for: operation), !hk.isEmpty {
                row += shortcutGap + (hk.displayString as NSString).size(withAttributes: attrs).width
            }
            maxContent = max(maxContent, row)
        }

        let bottomRows: [(String, String?, Bool)] = [
            (Strings.target(settingsStore.targetLanguage), nil, true),
            (Strings.history, "⌘H", false),
            (Strings.settings, "⌘,", false),
            (Strings.about, nil, false),
            (Strings.quit, "⌘Q", false)
        ]
        for (title, shortcut, hasSubmenu) in bottomRows {
            var row = (title as NSString).size(withAttributes: attrs).width
            if hasSubmenu { row += submenuChevron }
            if let shortcut {
                row += shortcutGap + (shortcut as NSString).size(withAttributes: attrs).width
            }
            maxContent = max(maxContent, row)
        }

        // One clean, roomy column: every custom row shares this width, and AppKit stretches
        // the standard rows (icons, key equivalents, submenu chevron) to it.
        return max(StatusMenuMetrics.minimumWidth, maxContent + horizontalPadding + StatusMenuMetrics.widthSlack)
    }

    @objc private func recheckAccessibilityAction() {
        PermissionsManager.requestAccessibility()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

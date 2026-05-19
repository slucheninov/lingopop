import AppKit
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let hotkeyManager = HotkeyManager()
    private let translationService = TranslationService()
    private let popup = PopupWindow()
    private let settingsStore = SettingsStore()
    private let historyStore = TranslationHistoryStore()
    private let statusController = StatusItemController()
    private lazy var settingsWindow = SettingsWindowController(
        store: settingsStore,
        providerImpls: translationService.providers
    )
    private lazy var historyWindow = HistoryWindowController(store: historyStore)
    private let log = Logger(subsystem: "com.lingopop.app", category: "AppDelegate")
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        setupStatusItem()
        registerHotkey()
        if !PermissionsManager.isAccessibilityGranted() {
            PermissionsManager.requestAccessibility()
        }
        migrateLegacyDevConfigIfNeeded()
        observeSettings()
        popup.state.onRetry = { [weak self] provider in
            self?.retryWith(provider)
        }
        popup.state.onReplace = { [weak self] text in
            self?.replaceSelectedText(with: text)
        }
        popup.state.onRetranslate = { [weak self] language in
            self?.retranslateWith(language)
        }
        popup.state.onRewrite = { [weak self] text in
            self?.rewriteResult(text)
        }
    }

    private var lastCapturedText: String?
    private var lastCursorPosition: NSPoint?
    private var lastDetectedSource: String?
    private var lastTargetLanguage: String?
    private var lastOperation: AIOperation = .translate

    private func observeSettings() {
        settingsStore.$hotkeys
            .removeDuplicates()
            .sink { [weak self] configs in
                self?.hotkeyManager.apply(configs)
                self?.statusController.statusItem?.menu.map { self?.rebuildMenu($0) }
            }
            .store(in: &cancellables)

        settingsStore.$launchAtLogin
            .removeDuplicates()
            .sink { enabled in
                LoginItemService.setEnabled(enabled)
            }
            .store(in: &cancellables)

        settingsStore.$targetLanguage
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.statusController.statusItem?.menu.map { self?.rebuildMenu($0) }
            }
            .store(in: &cancellables)

        settingsStore.$maxHistoryCount
            .removeDuplicates()
            .sink { [weak self] newMax in
                self?.historyStore.trim(to: newMax)
            }
            .store(in: &cancellables)

        settingsStore.$iCloudSync
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.historyStore.iCloudEnabled = enabled
                if enabled {
                    self?.settingsStore.reloadFromCloudIfNewer()
                    self?.historyStore.reloadFromCloudIfNewer()
                }
            }
            .store(in: &cancellables)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About LingoPop", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide LingoPop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "Quit LingoPop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func migrateLegacyDevConfigIfNeeded() {
        guard let legacy = DevConfigLoader.load(), !legacy.apiKey.isEmpty else { return }
        guard settingsStore.apiKey(for: legacy.providerType).isEmpty else { return }
        settingsStore.setApiKey(legacy.apiKey, for: legacy.providerType)
        settingsStore.activeProvider = legacy.providerType
        settingsStore.targetLanguage = legacy.targetLanguage
        settingsStore.updateSettings(
            .init(baseURL: legacy.baseURL, model: legacy.model),
            for: legacy.providerType
        )
        log.info("Migrated legacy dev config into SettingsStore")
    }

    private func setupStatusItem() {
        let menu = NSMenu()
        menu.delegate = self
        rebuildMenu(menu)
        let item = statusController.install(menu: menu)
        item.button?.toolTip = "LingoPop"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let menuCount = min(settingsStore.maxHistoryCount, 10)
        let recentEntries = Array(historyStore.entries.prefix(menuCount))
        if recentEntries.isEmpty {
            let placeholder = NSMenuItem(title: "No recent translations", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        } else {
            for entry in recentEntries {
                let fullText = historyMenuText(entry)
                let item = NSMenuItem(title: truncatedMenuText(fullText), action: #selector(copyHistoryItemAction(_:)), keyEquivalent: "")
                item.toolTip = fullText
                item.representedObject = entry.translated
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
                item.keyEquivalent = String(describing: key).lowercased()
                item.keyEquivalentModifierMask = hk.modifiers
            }
            item.representedObject = operation.rawValue
            item.image = NSImage(systemSymbolName: operation.systemImage, accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeLanguageSubmenu())
        menu.addItem(NSMenuItem(title: "History…", action: #selector(historyAction), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit LingoPop", action: #selector(quitAction), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
    }

    private func makeLanguageSubmenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Target: \(settingsStore.targetLanguage)", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Target language")
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

    private func registerHotkey() {
        hotkeyManager.onTrigger = { [weak self] operation in
            self?.handleHotkey(operation: operation)
        }
        hotkeyManager.apply(settingsStore.hotkeys)
    }

    private func handleHotkey(operation: AIOperation) {
        guard PermissionsManager.isAccessibilityGranted() else {
            DispatchQueue.main.async {
                self.showAccessibilityHelpAlert()
            }
            return
        }
        Task { @MainActor in
            do {
                let captured = try await TextCapture.capture()
                self.log.info("Captured: \(captured.text, privacy: .public)")
                let limit = self.settingsStore.maxInputChars
                if limit > 0, captured.text.count > limit {
                    self.statusController.apply(.error)
                    self.popup.state.setError("Text is \(captured.text.count) characters, max is \(limit). Adjust in Settings → Main.")
                    self.popup.show(near: captured.cursorPosition)
                    return
                }
                let detectedSource = operation == .translate ? LanguageDetector.detect(captured.text) : nil
                let targetLanguage = operation == .translate ? self.resolveTargetLanguage(detectedSource: detectedSource) : self.settingsStore.targetLanguage
                self.lastCapturedText = captured.text
                self.lastCursorPosition = captured.cursorPosition
                self.lastDetectedSource = detectedSource
                self.lastTargetLanguage = targetLanguage
                self.lastOperation = operation
                await self.runOperation(
                    operation: operation,
                    text: captured.text,
                    cursorPosition: captured.cursorPosition,
                    detectedSource: detectedSource,
                    targetLanguage: targetLanguage,
                    primary: self.settingsStore.activeProvider,
                    allowFallback: true
                )
            } catch TextCaptureError.emptySelection {
                self.statusController.apply(.error)
                self.popup.state.setError("Nothing selected. Select some text first, then press the hotkey.")
                self.popup.show(near: NSEvent.mouseLocation)
            } catch TextCaptureError.clipboardTimeout {
                self.statusController.apply(.error)
                self.popup.state.setError("Clipboard didn't update in time. Try again.")
                self.popup.show(near: NSEvent.mouseLocation)
            } catch {
                self.statusController.apply(.error)
                self.popup.state.setError("\(error)")
                self.popup.show(near: NSEvent.mouseLocation)
            }
        }
    }

    private func runOperation(
        operation: AIOperation,
        text: String,
        cursorPosition: NSPoint,
        detectedSource: String?,
        targetLanguage: String,
        primary: ProviderType,
        allowFallback: Bool
    ) async {
        let primaryConfig = settingsStore.config(for: primary, overrideTargetLanguage: targetLanguage)
        let primaryImpl = translationService.providers[primary]
        if primaryImpl?.supportedOperations.contains(operation) == false {
            statusController.apply(.error)
            popup.state.setError(TranslationError.operationNotSupported(provider: primary, operation: operation).errorDescription ?? "")
            popup.state.availableRetryProviders = retryProviders(excluding: primary, for: operation)
            popup.show(near: cursorPosition)
            return
        }
        let primaryRequiresKey = primaryImpl?.requiresApiKey ?? true
        if primaryRequiresKey, primaryConfig.apiKey.isEmpty {
            statusController.apply(.error)
            popup.state.setError("API key missing for \(primary.rawValue). Open Settings → Provider to add one.")
            popup.state.availableRetryProviders = retryProviders(excluding: primary, for: operation)
            popup.show(near: cursorPosition)
            return
        }
        statusController.apply(.translating)
        popup.state.setLoading(operation: operation, original: text)
        popup.show(near: cursorPosition)

        do {
            let result = try await translationService.execute(text: text, operation: operation, config: primaryConfig)
            present(result: result, source: detectedSource, viaFallback: false)
            return
        } catch let primaryError as TranslationError {
            if allowFallback,
               let fallback = settingsStore.fallback(for: primary),
               fallback != primary,
               isProviderReady(fallback, for: operation),
               shouldRetryWithFallback(primaryError) {
                let fallbackConfig = settingsStore.config(for: fallback, overrideTargetLanguage: targetLanguage)
                do {
                    var result = try await translationService.execute(text: text, operation: operation, config: fallbackConfig)
                    result.viaFallback = true
                    present(result: result, source: detectedSource, viaFallback: true)
                    return
                } catch {
                    log.error("Fallback also failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            statusController.apply(.error)
            popup.state.setError(primaryError.errorDescription ?? "\(primaryError)")
            popup.state.availableRetryProviders = retryProviders(excluding: primary, for: operation)
        } catch {
            statusController.apply(.error)
            popup.state.setError("\(error)")
            popup.state.availableRetryProviders = retryProviders(excluding: primary, for: operation)
        }
    }

    private func present(result: TranslationResult, source: String?, viaFallback: Bool) {
        popup.state.setResult(result)
        popup.state.availableRetryProviders = retryProviders(excluding: result.provider, for: result.operation)
        statusController.apply(.idle)
        let entry = TranslationHistoryEntry(
            original: result.original,
            translated: result.translated,
            sourceLanguage: source,
            targetLanguage: result.targetLanguage,
            provider: result.provider,
            operation: result.operation
        )
        historyStore.add(entry, maxCount: settingsStore.maxHistoryCount)
    }

    private func retryProviders(excluding: ProviderType, for operation: AIOperation) -> [ProviderType] {
        ProviderType.allCases.filter {
            $0 != excluding && isProviderReady($0, for: operation)
        }
    }

    private func isProviderReady(_ provider: ProviderType, for operation: AIOperation) -> Bool {
        guard let impl = translationService.providers[provider] else { return false }
        guard impl.supportedOperations.contains(operation) else { return false }
        if !impl.requiresApiKey { return true }
        return settingsStore.hasApiKey(for: provider)
    }

    private func shouldRetryWithFallback(_ error: TranslationError) -> Bool {
        switch error {
        case .http(let status, _, _):
            return status == 429 || (500...599).contains(status)
        case .network:
            return true
        case .invalidURL, .missingApiKey, .decoding, .emptyResponse, .operationNotSupported:
            return false
        }
    }

    private func retryWith(_ provider: ProviderType) {
        guard let text = lastCapturedText,
              let cursor = lastCursorPosition,
              let target = lastTargetLanguage else { return }
        let operation = lastOperation
        Task { @MainActor in
            await self.runOperation(
                operation: operation,
                text: text,
                cursorPosition: cursor,
                detectedSource: self.lastDetectedSource,
                targetLanguage: target,
                primary: provider,
                allowFallback: false
            )
        }
    }

    private func rewriteResult(_ text: String) {
        guard let cursor = lastCursorPosition,
              let target = lastTargetLanguage else { return }
        Task { @MainActor in
            await self.runOperation(
                operation: .rewrite,
                text: text,
                cursorPosition: cursor,
                detectedSource: nil,
                targetLanguage: target,
                primary: self.settingsStore.activeProvider,
                allowFallback: true
            )
        }
    }

    private func retranslateWith(_ targetLanguage: String) {
        guard let text = lastCapturedText,
              let cursor = lastCursorPosition else { return }
        lastTargetLanguage = targetLanguage
        Task { @MainActor in
            await self.runOperation(
                operation: .translate,
                text: text,
                cursorPosition: cursor,
                detectedSource: self.lastDetectedSource,
                targetLanguage: targetLanguage,
                primary: self.settingsStore.activeProvider,
                allowFallback: true
            )
        }
    }

    private func replaceSelectedText(with text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        popup.close()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            simulateCommandV()
        }
    }

    private func simulateCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(0x09) // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func resolveTargetLanguage(detectedSource: String?) -> String {
        guard settingsStore.useAutoDetect, let source = detectedSource else {
            return settingsStore.targetLanguage
        }
        if let mapped = settingsStore.languagePairs[source] {
            return mapped
        }
        return settingsStore.targetLanguage
    }

    private func showAccessibilityHelpAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility access required"
        alert.informativeText = """
        Steps:
        1. Open System Settings → Privacy & Security → Accessibility
        2. Make sure LingoPop is in the list and the toggle is ON
        3. Quit LingoPop completely (menu bar → Quit) and relaunch

        macOS only reads the new permission after a full restart of the app.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit LingoPop")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            PermissionsManager.openAccessibilitySettings()
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }

    @objc private func operationMenuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let op = AIOperation(rawValue: raw) else { return }
        handleHotkey(operation: op)
    }

    @objc private func selectLanguageAction(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? String else { return }
        settingsStore.targetLanguage = lang
        settingsStore.save()
    }

    @objc private func settingsAction() {
        settingsWindow.show()
    }

    @objc private func historyAction() {
        historyWindow.show()
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

    private func truncatedMenuText(_ text: String) -> String {
        let font = NSFont.menuFont(ofSize: 0)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let maxWidth: CGFloat = 270
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

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

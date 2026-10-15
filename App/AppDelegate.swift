import AppKit
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    // Members below without `private` are used by the `AppDelegate+PopupActions.swift`
    // extension (Swift `private` does not cross files).
    private let hotkeyManager = HotkeyManager()
    let translationService = TranslationService()
    /// Created lazily so it can be handed `self` as its (weakly held) `PopupActions`.
    /// This is the only place the popup is wired to its actions.
    lazy var popup = PopupWindow(actions: self)
    let settingsStore = SettingsStore()
    private let historyStore = TranslationHistoryStore()
    private let usageStore = UsageStore()
    let statusController = StatusItemController()
    private lazy var operationRunner = OperationRunner(
        settingsStore: settingsStore,
        translationService: translationService
    )
    private lazy var settingsWindow = SettingsWindowController(
        store: settingsStore,
        usageStore: usageStore,
        providerImpls: translationService.providers
    )
    private lazy var historyWindow = HistoryWindowController(store: historyStore)
    let log = Logger(subsystem: "com.lingopop.app", category: "AppDelegate")
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        setupStatusItem()
        registerHotkey()
        if !PermissionsManager.isAccessibilityGranted() {
            PermissionsManager.requestAccessibility()
        }
        migrateLegacyDevConfigIfNeeded()
        translationService.usageStore = usageStore
        observeSettings()
        UpdateChecker.shared.startPeriodicChecks()
    }

    enum Timing {
        /// Delay to restore focus before screen capture
        static let focusRestoreDelay: UInt64 = 150_000_000  // 150ms
        /// Delay after closing popup before paste (covers close animation)
        static let pasteDelay: UInt64 = 200_000_000         // 200ms
        /// Best-effort delay after paste before restoring the user's clipboard
        static let clipboardRestoreDelay: UInt64 = 150_000_000 // 150ms
    }

    // Session state of the last operation (Retry / Rewrite / Explain re-run from it).
    var lastCapturedText: String?
    var lastCursorPosition: NSPoint?
    var lastDetectedSource: String?
    var lastTargetLanguage: String?
    var lastOperation: AIOperation = .translate
    var lastCapturedImage: NSImage?
    private var currentScreenTranslateTask: Task<Void, Never>?
    private var screenTranslateToken: UUID?
    private var currentOperationTask: Task<Void, Never>?
    private var operationTaskToken: UUID?
    var previousApp: NSRunningApplication?

    private func observeSettings() {
        settingsStore.$hotkeys
            .removeDuplicates()
            .sink { [weak self] configs in
                self?.hotkeyManager.apply(configs)
            }
            .store(in: &cancellables)

        settingsStore.$launchAtLogin
            .removeDuplicates()
            .sink { enabled in
                LoginItemService.setEnabled(enabled)
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
                guard let self else { return }
                self.historyStore.iCloudEnabled = enabled
                self.usageStore.iCloudEnabled = enabled
                if enabled {
                    self.settingsStore.reloadFromCloudIfNewer()
                    self.historyStore.reloadFromCloudIfNewer()
                    self.usageStore.reloadFromCloudIfNewer()
                }
            }
            .store(in: &cancellables)

        settingsStore.$syncHistoryToiCloud
            .removeDuplicates()
            .sink { [weak self] sync in
                self?.historyStore.syncHistoryToiCloud = sync
                if sync { self?.historyStore.reloadFromCloudIfNewer() }
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
        let devConfigPath = NSHomeDirectory() + "/.lingopop-dev.json"
        do {
            try FileManager.default.removeItem(atPath: devConfigPath)
            log.info("Removed dev config after migration")
        } catch {
            log.warning("Could not remove dev config: \(error.localizedDescription, privacy: .public)")
        }
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
            text: Self.historyHeaderText,
            width: rowWidth
        )
        header.isEnabled = false
        menu.addItem(header)

        if recentEntries.isEmpty {
            let placeholder = NSMenuItem(title: "No recent translations", action: nil, keyEquivalent: "")
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
        menu.addItem(NSMenuItem(title: "History…", action: #selector(historyAction), keyEquivalent: "h"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ","))
        if !PermissionsManager.isAccessibilityGranted() {
            menu.addItem(NSMenuItem.separator())
            let item = NSMenuItem(title: "⚠ Re-check Accessibility…", action: #selector(recheckAccessibilityAction), keyEquivalent: "")
            menu.addItem(item)
        }
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

    /// Runs `body` as the single tracked operation task. Any previous operation is
    /// cancelled first; an identity token makes sure the old task's cleanup never
    /// clears the handle of the new one.
    func startOperationTask(_ body: @escaping @MainActor () async -> Void) {
        currentOperationTask?.cancel()
        let token = UUID()
        operationTaskToken = token
        currentOperationTask = Task { @MainActor in
            defer {
                if self.operationTaskToken == token {
                    self.currentOperationTask = nil
                    self.operationTaskToken = nil
                }
            }
            await body()
        }
    }

    private func handleHotkey(operation: AIOperation) {
        if operation == .screenTranslate {
            handleScreenTranslateHotkey()
            return
        }
        guard PermissionsManager.isAccessibilityGranted() else {
            PermissionAlert.show(.accessibility)
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        startOperationTask {
            do {
                let captured = try await TextCapture.capture()
                self.log.info("Captured: \(captured.text, privacy: .private)")
                let limit = self.settingsStore.maxInputChars
                if limit > 0, captured.text.count > limit {
                    self.presentFailure(
                        PopupError(message: "Text is \(captured.text.count) characters, max is \(limit). Adjust in Settings → Main."),
                        near: captured.cursorPosition
                    )
                    return
                }
                let detectedSource = operation == .translate ? LanguageDetector.detect(captured.text) : nil
                let targetLanguage = operation == .translate ? self.resolveTargetLanguage(detectedSource: detectedSource) : self.settingsStore.targetLanguage
                await self.runOperation(
                    operation: operation,
                    text: captured.text,
                    cursorPosition: captured.cursorPosition,
                    detectedSource: detectedSource,
                    targetLanguage: targetLanguage,
                    primary: self.settingsStore.activeProvider,
                    allowFallback: true
                )
            } catch is CancellationError {
                return
            } catch {
                self.presentFailure(error, near: NSEvent.mouseLocation)
            }
        }
    }

    private func handleScreenTranslateHotkey() {
        if !PermissionsManager.isScreenRecordingGranted() {
            // Show system TCC prompt first (macOS 15+). If still denied, show manual instructions.
            guard PermissionsManager.requestScreenCaptureAccess() else {
                PermissionAlert.show(.screenRecording)
                return
            }
        }
        currentScreenTranslateTask?.cancel()
        let token = UUID()
        screenTranslateToken = token
        previousApp = NSWorkspace.shared.frontmostApplication
        currentScreenTranslateTask = Task { @MainActor in
            defer {
                if screenTranslateToken == token {
                    currentScreenTranslateTask = nil
                    screenTranslateToken = nil
                }
            }
            lastCapturedText = nil
            do {
                let screenRect = try await CaptureOverlayWindow.runSelection()
                // Restore previous app and give the OS 150 ms to transfer focus so
                // any subsequent Cmd+C (regular translate) goes to the right app.
                previousApp?.activate(options: .activateIgnoringOtherApps)
                try await Task.sleep(nanoseconds: Timing.focusRestoreDelay)

                let cgImage = try ScreenCapture.capture(rect: screenRect)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                lastCapturedImage = nsImage

                let popupAnchor = NSPoint(x: screenRect.maxX, y: screenRect.minY)
                lastCursorPosition = popupAnchor
                lastTargetLanguage = resolveTargetLanguage(detectedSource: nil)
                lastOperation = .screenTranslate

                statusController.apply(.translating)
                popup.state.setLoading(operation: .screenTranslate, original: "")
                popup.show(near: popupAnchor)

                let ocrText: String
                do {
                    ocrText = try await ScreenOCR.recognize(image: cgImage)
                } catch is CancellationError {
                    return
                } catch {
                    let retryProviders = visionCapableProviders()
                    var failure = PopupError.from(error)
                    if case ScreenOCRError.noTextFound = error, !retryProviders.isEmpty {
                        failure = PopupError(message: ScreenOCRError.noTextFoundRetryHint)
                    }
                    presentFailure(failure, retryProviders: retryProviders)
                    return
                }

                let detectedSource = LanguageDetector.detect(ocrText)
                let targetLanguage = resolveTargetLanguage(detectedSource: detectedSource)
                lastCapturedText = ocrText
                lastDetectedSource = detectedSource
                lastTargetLanguage = targetLanguage

                // Auto-copy the OCR text so it's immediately available
                if settingsStore.autoCopyOCR {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ocrText, forType: .string)
                }

                statusController.apply(.idle)
                popup.state.setOCR(ocrText)
                popup.state.availableRetryProviders = visionCapableProviders()
                popup.state.availableTranslateProviders = translateProviders()
                popup.state.activeTranslateProvider = settingsStore.activeProvider
            } catch CaptureOverlayError.cancelled {
                previousApp?.activate(options: .activateIgnoringOtherApps)
            } catch is CancellationError {
                return
            } catch {
                previousApp?.activate(options: .activateIgnoringOtherApps)
                presentFailure(error, near: NSEvent.mouseLocation)
            }
        }
    }

    func runOperation(
        operation: AIOperation,
        text: String,
        cursorPosition: NSPoint,
        detectedSource: String?,
        targetLanguage: String,
        primary: ProviderType,
        allowFallback: Bool
    ) async {
        // Single choke point for session state: Retry always re-runs the *last*
        // operation on the *current* text. The captured image only stays relevant
        // for Screen Translate itself.
        lastOperation = operation
        lastCapturedText = text
        lastCursorPosition = cursorPosition
        lastDetectedSource = detectedSource
        lastTargetLanguage = targetLanguage
        if operation != .screenTranslate {
            lastCapturedImage = nil
        }

        statusController.apply(.translating)
        popup.state.setLoading(operation: operation, original: text)
        popup.show(near: cursorPosition)

        do {
            let outcome = try await operationRunner.run(
                operation: operation,
                text: text,
                detectedSource: detectedSource,
                targetLanguage: targetLanguage,
                primary: primary,
                allowFallback: allowFallback
            )
            present(result: outcome.result, source: outcome.detectedSource, viaFallback: outcome.viaFallback)
        } catch is CancellationError {
            // Superseded by a newer operation, which owns the popup now.
            return
        } catch {
            let failure: PopupError
            if case TranslationError.missingApiKey = error {
                failure = PopupError(message: "API key missing for \(primary.rawValue). Open Settings → Providers to add one.")
            } else {
                failure = PopupError.from(error)
            }
            presentFailure(failure, retryProviders: retryProviders(excluding: primary, for: operation))
        }
    }

    /// Shows `failure` in the popup (error status icon, optional Retry providers and,
    /// when `anchor` is given, the popup itself). The single error-presentation path.
    func presentFailure(_ failure: PopupError, retryProviders: [ProviderType] = [], near anchor: NSPoint? = nil) {
        statusController.apply(.error)
        popup.state.setError(failure)
        popup.state.availableRetryProviders = retryProviders
        if let anchor { popup.show(near: anchor) }
    }

    /// Maps any error through `PopupError.from`. `CancellationError` is never presented.
    func presentFailure(_ error: Error, retryProviders: [ProviderType] = [], near anchor: NSPoint? = nil) {
        guard !(error is CancellationError) else { return }
        presentFailure(PopupError.from(error), retryProviders: retryProviders, near: anchor)
    }

    func present(result: TranslationResult, source: String?, viaFallback: Bool) {
        if result.operation == .screenTranslate, settingsStore.autoCopyOCR {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.translated, forType: .string)
        }
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
        ProviderType.allCases.filter { type in
            guard type != excluding, isProviderReady(type, for: operation) else { return false }
            if operation == .screenTranslate {
                return translationService.providers[type]?.supportsVision == true
            }
            return true
        }
    }

    func visionCapableProviders(excluding: ProviderType? = nil) -> [ProviderType] {
        ProviderType.allCases.filter { type in
            guard type != excluding else { return false }
            guard let impl = translationService.providers[type] else { return false }
            guard impl.supportsVision else { return false }
            if impl.requiresApiKey { return settingsStore.hasApiKey(for: type) }
            return true
        }
    }

    private func translateProviders() -> [ProviderType] {
        ProviderType.allCases.filter { isProviderReady($0, for: .screenTranslate) }
    }

    private func isProviderReady(_ provider: ProviderType, for operation: AIOperation) -> Bool {
        guard let impl = translationService.providers[provider] else { return false }
        guard impl.supportedOperations.contains(operation) else { return false }
        if !impl.requiresApiKey { return true }
        return settingsStore.hasApiKey(for: provider)
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

    private static let historyHeaderText = "Select the clip you want to add to your clipboard"

    private func statusMenuRowWidth() -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let iconAndGap = StatusMenuMetrics.iconSize + StatusMenuMetrics.iconTitleGap
        let shortcutGap = StatusMenuMetrics.titleShortcutGap
        let submenuChevron: CGFloat = 14
        let horizontalPadding = StatusMenuMetrics.horizontalInset * 2
        var maxContent: CGFloat = (Self.historyHeaderText as NSString).size(withAttributes: attrs).width

        for operation in AIOperation.allCases {
            var row = iconAndGap + (operation.displayName as NSString).size(withAttributes: attrs).width
            if let hk = settingsStore.hotkey(for: operation), !hk.isEmpty {
                row += shortcutGap + (hk.displayString as NSString).size(withAttributes: attrs).width
            }
            maxContent = max(maxContent, row)
        }

        let bottomRows: [(String, String?, Bool)] = [
            ("Target: \(settingsStore.targetLanguage)", nil, true),
            ("History…", "⌘H", false),
            ("Settings…", "⌘,", false),
            ("Quit LingoPop", "⌘Q", false)
        ]
        for (title, shortcut, hasSubmenu) in bottomRows {
            var row = (title as NSString).size(withAttributes: attrs).width
            if hasSubmenu { row += submenuChevron }
            if let shortcut {
                row += shortcutGap + (shortcut as NSString).size(withAttributes: attrs).width
            }
            maxContent = max(maxContent, row)
        }

        return max(340, maxContent + horizontalPadding) + 40
    }

    @objc private func recheckAccessibilityAction() {
        PermissionsManager.requestAccessibility()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

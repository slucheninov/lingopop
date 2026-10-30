import AppKit
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

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
    /// Session state of the last operation (Retry / Rewrite / Explain re-run from it).
    let session = OperationSession()
    private lazy var operationRunner = OperationRunner(
        settingsStore: settingsStore,
        translationService: translationService
    )
    lazy var presenter = OperationPresenter(
        popup: popup,
        statusController: statusController,
        settingsStore: settingsStore,
        historyStore: historyStore,
        translationService: translationService
    )
    private lazy var screenTranslateFlow = ScreenTranslateFlow(
        session: session,
        settingsStore: settingsStore,
        statusController: statusController,
        popup: popup,
        presenter: presenter
    )
    private lazy var statusMenu = StatusMenuController(
        settingsStore: settingsStore,
        historyStore: historyStore,
        actions: self
    )
    private lazy var settingsWindow = SettingsWindowController(
        store: settingsStore,
        usageStore: usageStore,
        providerImpls: translationService.providers
    )
    private lazy var historyWindow = HistoryWindowController(store: historyStore)
    let log = Logger(subsystem: "com.lingopop.app", category: "AppDelegate")
    private var cancellables: Set<AnyCancellable> = []
    private var currentOperationTask: Task<Void, Never>?
    private var operationTaskToken: UUID?

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
        appMenu.addItem(NSMenuItem(title: String(localized: "About LingoPop"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: String(localized: "Hide LingoPop"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: String(localized: "Quit LingoPop"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
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
        let item = statusController.install(menu: statusMenu.makeMenu())
        item.button?.toolTip = "LingoPop"
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
            screenTranslateFlow.start()
            return
        }
        guard PermissionsManager.isAccessibilityGranted() else {
            PermissionAlert.show(.accessibility)
            return
        }
        session.previousApp = NSWorkspace.shared.frontmostApplication
        startOperationTask {
            do {
                let captured = try await TextCapture.capture()
                self.log.info("Captured: \(captured.text, privacy: .private)")
                let limit = self.settingsStore.maxInputChars
                if limit > 0, captured.text.count > limit {
                    self.presenter.presentFailure(
                        PopupError(message: String(localized: "Text is \(String(captured.text.count)) characters, max is \(String(limit)). Adjust in Settings → Main.")),
                        near: captured.cursorPosition
                    )
                    return
                }
                let detectedSource = operation == .translate ? LanguageDetector.detect(captured.text) : nil
                let targetLanguage = operation == .translate ? self.settingsStore.resolveTargetLanguage(detectedSource: detectedSource) : self.settingsStore.targetLanguage
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
                self.presenter.presentFailure(error, near: NSEvent.mouseLocation)
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
        session.lastOperation = operation
        session.lastCapturedText = text
        session.lastCursorPosition = cursorPosition
        session.lastDetectedSource = detectedSource
        session.lastTargetLanguage = targetLanguage
        if operation != .screenTranslate {
            session.lastCapturedImage = nil
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
            presenter.present(result: outcome.result, source: outcome.detectedSource, viaFallback: outcome.viaFallback)
        } catch is CancellationError {
            // Superseded by a newer operation, which owns the popup now.
            return
        } catch {
            let failure: PopupError
            if case TranslationError.missingApiKey = error {
                failure = PopupError(message: String(localized: "API key missing for \(primary.displayName). Open Settings → Providers to add one."))
            } else {
                failure = PopupError.from(error)
            }
            presenter.presentFailure(failure, retryProviders: presenter.retryProviders(excluding: primary, for: operation))
        }
    }

}

extension AppDelegate: StatusMenuActions {
    func statusMenuDidSelect(operation: AIOperation) {
        handleHotkey(operation: operation)
    }

    func statusMenuDidRequestSettings() {
        settingsWindow.show()
    }

    func statusMenuDidRequestAbout() {
        settingsWindow.show(tab: .about)
    }

    func statusMenuDidRequestHistory() {
        historyWindow.show()
    }
}

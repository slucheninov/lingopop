import AppKit

/// Screen Translate: region selection -> screen capture -> OCR -> popup in the `.ocr`
/// phase. The follow-up translation (Translate button) goes through
/// `PopupActions.translateOCR`, not through this type.
@MainActor
final class ScreenTranslateFlow {
    private enum Timing {
        /// Delay to restore focus before screen capture
        static let focusRestoreDelay: UInt64 = 150_000_000  // 150ms
    }

    private let session: OperationSession
    private let settingsStore: SettingsStore
    private let statusController: StatusItemController
    private let popup: PopupWindow
    private let presenter: OperationPresenter
    private var currentTask: Task<Void, Never>?
    private var taskToken: UUID?

    init(
        session: OperationSession,
        settingsStore: SettingsStore,
        statusController: StatusItemController,
        popup: PopupWindow,
        presenter: OperationPresenter
    ) {
        self.session = session
        self.settingsStore = settingsStore
        self.statusController = statusController
        self.popup = popup
        self.presenter = presenter
    }

    func start() {
        if !PermissionsManager.isScreenRecordingGranted() {
            // Show system TCC prompt first (macOS 15+). If still denied, show manual instructions.
            guard PermissionsManager.requestScreenCaptureAccess() else {
                PermissionAlert.show(.screenRecording)
                return
            }
        }
        currentTask?.cancel()
        let token = UUID()
        taskToken = token
        session.previousApp = NSWorkspace.shared.frontmostApplication
        currentTask = Task { @MainActor in
            defer {
                if taskToken == token {
                    currentTask = nil
                    taskToken = nil
                }
            }
            session.lastCapturedText = nil
            do {
                let screenRect = try await CaptureOverlayWindow.runSelection()
                // Restore previous app and give the OS 150 ms to transfer focus so
                // any subsequent Cmd+C (regular translate) goes to the right app.
                session.previousApp?.activate(options: .activateIgnoringOtherApps)
                try await Task.sleep(nanoseconds: Timing.focusRestoreDelay)

                let cgImage = try await ScreenCapture.capture(rect: screenRect)
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                session.lastCapturedImage = nsImage

                let popupAnchor = NSPoint(x: screenRect.maxX, y: screenRect.minY)
                session.lastCursorPosition = popupAnchor
                session.lastTargetLanguage = settingsStore.resolveTargetLanguage(detectedSource: nil)
                session.lastOperation = .screenTranslate

                statusController.apply(.translating)
                popup.state.setLoading(operation: .screenTranslate, original: "")
                popup.show(near: popupAnchor)

                let ocrText: String
                do {
                    ocrText = try await ScreenOCR.recognize(image: cgImage)
                } catch is CancellationError {
                    return
                } catch {
                    let retryProviders = presenter.visionCapableProviders()
                    var failure = PopupError.from(error)
                    if case ScreenOCRError.noTextFound = error, !retryProviders.isEmpty {
                        failure = PopupError(message: ScreenOCRError.noTextFoundRetryHint)
                    }
                    presenter.presentFailure(failure, retryProviders: retryProviders)
                    return
                }

                let detectedSource = LanguageDetector.detect(ocrText)
                let targetLanguage = settingsStore.resolveTargetLanguage(detectedSource: detectedSource)
                session.lastCapturedText = ocrText
                session.lastDetectedSource = detectedSource
                session.lastTargetLanguage = targetLanguage

                // Auto-copy the OCR text so it's immediately available
                if settingsStore.autoCopyOCR {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ocrText, forType: .string)
                }

                statusController.apply(.idle)
                popup.state.setOCR(ocrText)
                popup.state.availableRetryProviders = presenter.visionCapableProviders()
                popup.state.availableTranslateProviders = presenter.translateProviders()
                popup.state.activeTranslateProvider = settingsStore.activeProvider
            } catch CaptureOverlayError.cancelled {
                session.previousApp?.activate(options: .activateIgnoringOtherApps)
            } catch is CancellationError {
                return
            } catch {
                session.previousApp?.activate(options: .activateIgnoringOtherApps)
                presenter.presentFailure(error, near: NSEvent.mouseLocation)
            }
        }
    }
}

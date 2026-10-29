import AppKit

/// Handlers for the actions raised by the popup UI (see `PopupActions`).
extension AppDelegate: PopupActions {

    func retry(with provider: ProviderType) {
        guard let cursor = session.lastCursorPosition,
              let target = session.lastTargetLanguage else { return }
        let operation = session.lastOperation

        if operation == .screenTranslate, let nsImage = session.lastCapturedImage {
            startOperationTask {
                guard let impl = self.translationService.providers[provider], impl.supportsVision else { return }
                let config = self.settingsStore.config(for: provider, overrideTargetLanguage: target)
                self.statusController.apply(.translating)
                self.popup.state.setLoading(operation: .screenTranslate, original: "")
                do {
                    guard let jpegData = self.jpegData(from: nsImage) else {
                        throw TranslationError.emptyResponse
                    }
                    let providerResult = try await impl.executeVision(image: jpegData, targetLanguage: target, config: config)
                    self.translationService.recordUsage(providerResult.usage, provider: provider, model: config.model, operation: .screenTranslate)
                    let result = TranslationResult(
                        original: self.session.lastCapturedText ?? "",
                        translated: providerResult.text,
                        targetLanguage: target,
                        provider: provider,
                        operation: .screenTranslate,
                        truncated: providerResult.truncated
                    )
                    self.presenter.present(result: result, source: self.session.lastDetectedSource, viaFallback: false)
                } catch {
                    self.presenter.presentFailure(error, retryProviders: self.presenter.visionCapableProviders(excluding: provider))
                }
            }
            return
        }

        guard let text = session.lastCapturedText else { return }
        startOperationTask {
            await self.runOperation(
                operation: operation,
                text: text,
                cursorPosition: cursor,
                detectedSource: self.session.lastDetectedSource,
                targetLanguage: target,
                primary: provider,
                allowFallback: false
            )
        }
    }

    func translateOCR(_ text: String, with provider: ProviderType) {
        guard let cursor = session.lastCursorPosition,
              let target = session.lastTargetLanguage else { return }
        let source = session.lastDetectedSource
        startOperationTask {
            await self.runOperation(
                operation: .screenTranslate,
                text: text,
                cursorPosition: cursor,
                detectedSource: source,
                targetLanguage: target,
                primary: provider,
                allowFallback: provider == self.settingsStore.activeProvider
            )
        }
    }

    func rewrite(_ text: String) {
        guard let cursor = session.lastCursorPosition,
              let target = session.lastTargetLanguage else { return }
        startOperationTask {
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

    func explain(_ text: String) {
        guard let cursor = session.lastCursorPosition,
              let target = session.lastTargetLanguage else { return }
        startOperationTask {
            await self.runOperation(
                operation: .explain,
                text: text,
                cursorPosition: cursor,
                detectedSource: nil,
                targetLanguage: target,
                primary: self.settingsStore.activeProvider,
                allowFallback: true
            )
        }
    }

    func retranslate(to targetLanguage: String) {
        guard let text = session.lastCapturedText,
              let cursor = session.lastCursorPosition else { return }
        startOperationTask {
            await self.runOperation(
                operation: .translate,
                text: text,
                cursorPosition: cursor,
                detectedSource: self.session.lastDetectedSource,
                targetLanguage: targetLanguage,
                primary: self.settingsStore.activeProvider,
                allowFallback: true
            )
        }
    }

    func replace(with text: String) {
        let replacer = TextReplacer(text: text)
        let targetApp = session.previousApp
        let errorAnchor = session.lastCursorPosition ?? NSEvent.mouseLocation
        popup.close()
        statusController.apply(.idle)
        startOperationTask {
            await replacer.paste(into: targetApp) {
                self.presenter.presentFailure(
                    PopupError(message: String(localized: "Couldn't switch back to the original app, so nothing was replaced. The text is on your clipboard; paste it manually with ⌘V.")),
                    near: errorAnchor
                )
            }
        }
    }

    func popupDidClose() {
        session.lastCapturedText = nil
        session.lastCapturedImage = nil
    }

    // MARK: - Helpers

    private func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }
}

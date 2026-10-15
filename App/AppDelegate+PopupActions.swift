import AppKit

/// Handlers for the actions raised by the popup UI (see `PopupActions`).
extension AppDelegate: PopupActions {

    func retry(with provider: ProviderType) {
        guard let cursor = lastCursorPosition,
              let target = lastTargetLanguage else { return }
        let operation = lastOperation

        if operation == .screenTranslate, let nsImage = lastCapturedImage {
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
                        original: self.lastCapturedText ?? "",
                        translated: providerResult.text,
                        targetLanguage: target,
                        provider: provider,
                        operation: .screenTranslate,
                        truncated: providerResult.truncated
                    )
                    self.present(result: result, source: self.lastDetectedSource, viaFallback: false)
                } catch {
                    self.presentFailure(error, retryProviders: self.visionCapableProviders(excluding: provider))
                }
            }
            return
        }

        guard let text = lastCapturedText else { return }
        startOperationTask {
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

    func translateOCR(_ text: String, with provider: ProviderType) {
        guard let cursor = lastCursorPosition,
              let target = lastTargetLanguage else { return }
        let source = lastDetectedSource
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
        guard let cursor = lastCursorPosition,
              let target = lastTargetLanguage else { return }
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
        guard let cursor = lastCursorPosition,
              let target = lastTargetLanguage else { return }
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
        guard let text = lastCapturedText,
              let cursor = lastCursorPosition else { return }
        startOperationTask {
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

    func replace(with text: String) {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        let ownChangeCount = PasteboardSnapshot.writeTemporary(text, to: pasteboard)
        let targetApp = previousApp
        let errorAnchor = lastCursorPosition ?? NSEvent.mouseLocation
        popup.close()
        statusController.apply(.idle)
        startOperationTask {
            var pasted = false
            defer {
                // Only restore the user's clipboard if nobody wrote to it since our write.
                if pasteboard.changeCount == ownChangeCount {
                    if pasted {
                        snapshot.restore(to: pasteboard)
                    } else {
                        // Paste failed or was cancelled: leave the text as a normal
                        // (non-transient) clipboard entry so the user can paste manually.
                        pasteboard.clearContents()
                        pasteboard.setString(text, forType: .string)
                    }
                }
            }
            do {
                try await Task.sleep(nanoseconds: Timing.pasteDelay)
                guard let targetApp, await self.activateAndConfirm(targetApp) else {
                    self.presentFailure(
                        PopupError(message: "Couldn't switch back to the original app, so nothing was replaced. The text is on your clipboard; paste it manually with ⌘V."),
                        near: errorAnchor
                    )
                    return
                }
                KeyboardSimulator.simulateCommandV()
                pasted = true
                try await Task.sleep(nanoseconds: Timing.clipboardRestoreDelay)
            } catch {
                // Cancelled. If the paste already went out, `pasted` restores the clipboard.
                return
            }
        }
    }

    func popupDidClose() {
        lastCapturedText = nil
        lastCapturedImage = nil
    }

    // MARK: - Helpers

    private func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
    }

    /// Activates `app` and polls (up to ~300 ms) until it is actually frontmost.
    private func activateAndConfirm(_ app: NSRunningApplication) async -> Bool {
        let pid = app.processIdentifier
        app.activate(options: .activateIgnoringOtherApps)
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
}

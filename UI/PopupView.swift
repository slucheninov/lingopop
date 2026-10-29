import SwiftUI
import AppKit

struct PopupView: View {

    @ObservedObject var state: PopupState
    var onClose: () -> Void

    @AppStorage(PopupPrefs.fontSizeKey) private var popupFontSize: Double = PopupPrefs.defaultFontSize

    var body: some View {
        VStack(alignment: .leading, spacing: PopupLayout.stackSpacing) {
            dragHandle
            content
        }
        .padding(PopupLayout.contentPadding)
        .frame(width: layout.dynamicWidth(for: state.phase), alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: PopupLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PopupLayout.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private var layout: PopupLayout { PopupLayout(fontSize: popupFontSize) }

    private var dragHandle: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 28, height: 3)
            Spacer()
        }
        .frame(height: 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .overlay(WindowDragHandle())
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .loading(let operation, let preview):
            LoadingContent(operation: operation, preview: preview)
        case .ocr(let text):
            OCRContent(state: state, text: text, fontSize: popupFontSize)
        case .result(let result):
            ResultContent(state: state, result: result, fontSize: popupFontSize)
        case .error(let error):
            ErrorContent(state: state, error: error)
        }
    }

}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - Loading

private struct LoadingContent: View {
    let operation: AIOperation
    let preview: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("\(operation.displayName)…")
                .font(.system(size: 13, weight: .medium))
            Spacer(minLength: 0)
        }
        if !preview.isEmpty {
            Text(preview)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

// MARK: - OCR

private struct OCRContent: View {
    @ObservedObject var state: PopupState
    let text: String
    let fontSize: Double

    var body: some View {
        let header = PopupLayout(fontSize: fontSize).headerFontSize
        HStack(spacing: 4) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: header, weight: .semibold))
            Text("Recognized text")
                .font(.system(size: header, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        Text(text)
            .font(.system(size: CGFloat(fontSize)))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
        HStack(spacing: 8) {
            PopupActionButton(title: "Copy", systemImage: "doc.on.doc") { copyToPasteboard(text) }
            translateControls
            Spacer(minLength: 0)
            RetryMenu(state: state)
        }
    }

    private var translateControls: some View {
        HStack(spacing: 4) {
            Button(action: {
                let provider = state.activeTranslateProvider ?? state.availableTranslateProviders.first
                guard let provider else { return }
                state.actions?.translateOCR(text, with: provider)
            }) {
                Label("Translate", systemImage: "globe")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .popupButtonHelp("Translate with active provider")

            if !state.availableTranslateProviders.isEmpty {
                Menu {
                    ForEach(state.availableTranslateProviders, id: \.self) { provider in
                        Button {
                            state.actions?.translateOCR(text, with: provider)
                        } label: {
                            HStack {
                                Label(provider.displayName, systemImage: provider.sfSymbol)
                                if provider == state.activeTranslateProvider {
                                    Spacer(minLength: 8)
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(minWidth: 14, minHeight: 14)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popupButtonHelp("Translate with…")
            }
        }
    }
}

// MARK: - Result

private struct ResultContent: View {
    @ObservedObject var state: PopupState
    let result: TranslationResult
    let fontSize: Double

    var body: some View {
        ResultHeader(state: state, result: result, fontSize: fontSize)
        if let fallback = result.fallbackInfo {
            FallbackDisclosure(fallback: fallback)
        }
        Text(result.translated)
            .font(.system(size: CGFloat(fontSize)))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
        if result.truncated {
            Label("Response was truncated", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
        }
        ResultActionBar(state: state, result: result)
    }
}

private struct ResultHeader: View {
    @ObservedObject var state: PopupState
    let result: TranslationResult
    let fontSize: Double

    var body: some View {
        let header = PopupLayout(fontSize: fontSize).headerFontSize
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: result.provider.sfSymbol)
                    .font(.system(size: header, weight: .semibold))
                    .foregroundStyle(result.provider.iconColor)
                if result.operation == .translate {
                    Text("\(result.provider.displayName) →")
                        .font(.system(size: header, weight: .semibold))
                    Menu {
                        ForEach(languageOptions(current: result.targetLanguage), id: \.self) { lang in
                            Button {
                                state.actions?.retranslate(to: lang)
                            } label: {
                                if lang == result.targetLanguage {
                                    Label(lang, systemImage: "checkmark")
                                } else {
                                    Text(lang)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(result.targetLanguage)
                                .font(.system(size: header, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: max(6, header - 2), weight: .semibold))
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                } else {
                    Text(result.provider.displayName)
                        .font(.system(size: header, weight: .semibold))
                }
            }
            .foregroundStyle(.secondary)
            if result.viaFallback {
                Text("fallback")
                    .font(.system(size: max(7, header - 1), weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.orange.opacity(0.2)))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func languageOptions(current: String) -> [String] {
        var list = Languages.quickList
        if !list.contains(current) {
            list.insert(current, at: 0)
        }
        return list
    }
}

private struct FallbackDisclosure: View {
    let fallback: FallbackInfo

    var body: some View {
        DisclosureGroup("Why fallback was used") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(fallback.primaryProvider.displayName): \(fallback.message)")
                    .fixedSize(horizontal: false, vertical: true)
                if let details = fallback.details {
                    Text(details)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(size: 11))
        .tint(.orange)
    }
}

private struct ResultActionBar: View {
    @ObservedObject var state: PopupState
    let result: TranslationResult

    var body: some View {
        HStack(spacing: 8) {
            PopupActionButton(title: "Copy", systemImage: "doc.on.doc") { copyToPasteboard(result.translated) }
            if result.operation != .screenTranslate {
                PopupActionButton(title: "Replace", systemImage: "arrow.uturn.left") {
                    state.actions?.replace(with: result.translated)
                }
            }
            PopupActionButton(title: "Rewrite", systemImage: "wand.and.stars") {
                state.actions?.rewrite(result.translated)
            }
            if result.operation != .explain {
                PopupActionButton(title: "Explain", systemImage: "text.magnifyingglass") {
                    state.actions?.explain(result.translated)
                }
            }
            Spacer(minLength: 0)
            RetryMenu(state: state)
        }
    }
}

// MARK: - Error

private struct ErrorContent: View {
    @ObservedObject var state: PopupState
    let error: PopupError

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("Error")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
        }
        Text(error.message)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
        if let details = error.details {
            DisclosureGroup("Details") {
                Text(details)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))
            .tint(.accentColor)
        }
        if !state.availableRetryProviders.isEmpty {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                RetryMenu(state: state)
            }
        }
    }
}

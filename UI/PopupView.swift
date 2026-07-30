import SwiftUI
import AppKit

struct PopupView: View {

    @ObservedObject var state: PopupState
    var onClose: () -> Void

    @AppStorage("LingoPop.popupFontSize") private var popupFontSize: Double = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            dragHandle
            content
        }
        .padding(14)
        .frame(width: dynamicWidth, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

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
        case .ocr(let text):
            HStack(spacing: 4) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: headerFontSize, weight: .semibold))
                Text("Recognized text")
                    .font(.system(size: headerFontSize, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: CGFloat(popupFontSize)))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
            HStack(spacing: 8) {
                Button(action: { copy(text) }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popupButtonHelp("Copy")
                HStack(spacing: 4) {
                    Button(action: {
                        let provider = state.activeTranslateProvider ?? state.availableTranslateProviders.first
                        guard let provider else { return }
                        state.onTranslate?(text, provider)
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
                                    state.onTranslate?(text, provider)
                                } label: {
                                    HStack {
                                        Label(provider.rawValue, systemImage: provider.sfSymbol)
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
                Spacer(minLength: 0)
                if !state.availableRetryProviders.isEmpty {
                    Menu {
                        ForEach(state.availableRetryProviders, id: \.self) { provider in
                            Button {
                                state.onRetry?(provider)
                            } label: {
                                Label("Retry with \(provider.rawValue)", systemImage: provider.sfSymbol)
                            }
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .menuIndicator(.visible)
                    .fixedSize()
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        case .result(let result):
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: result.provider.sfSymbol)
                        .font(.system(size: headerFontSize, weight: .semibold))
                        .foregroundStyle(result.provider.iconColor)
                    if result.operation == .translate {
                        Text("\(result.provider.rawValue) →")
                            .font(.system(size: headerFontSize, weight: .semibold))
                        Menu {
                            ForEach(languageOptions(current: result.targetLanguage), id: \.self) { lang in
                                Button {
                                    state.onRetranslate?(lang)
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
                                    .font(.system(size: headerFontSize, weight: .semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: max(6, headerFontSize - 2), weight: .semibold))
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                    } else {
                        Text(result.provider.rawValue)
                            .font(.system(size: headerFontSize, weight: .semibold))
                    }
                }
                .foregroundStyle(.secondary)
                if result.viaFallback {
                    Text("fallback")
                        .font(.system(size: max(7, headerFontSize - 1), weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                }
            }
            Text(result.translated)
                .font(.system(size: CGFloat(popupFontSize)))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
            HStack(spacing: 8) {
                Button(action: { copy(result.translated) }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popupButtonHelp("Copy")
                if result.operation != .screenTranslate {
                    Button(action: { state.onReplace?(result.translated) }) {
                        Label("Replace", systemImage: "arrow.uturn.left")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popupButtonHelp("Replace")
                }
                Button(action: { state.onRewrite?(result.translated) }) {
                    Label("Rewrite", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .popupButtonHelp("Rewrite")
                if result.operation != .explain {
                    Button(action: { state.onExplain?(result.translated) }) {
                        Label("Explain", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popupButtonHelp("Explain")
                }
                Spacer(minLength: 0)
                if !state.availableRetryProviders.isEmpty {
                    Menu {
                        ForEach(state.availableRetryProviders, id: \.self) { provider in
                            Button {
                                state.onRetry?(provider)
                            } label: {
                                Label("Retry with \(provider.rawValue)", systemImage: provider.sfSymbol)
                            }
                        }
                    } label: {
                        Label("Retry", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .menuIndicator(.visible)
                    .fixedSize()
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        case .error(let error):
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
        }
    }

    private var headerFontSize: CGFloat { max(8, CGFloat(popupFontSize) - 2) }

    private var dynamicWidth: CGFloat {
        let minW = max(320, headerFontSize * 30)
        let text: String
        switch state.phase {
        case .result(let result): text = result.translated
        case .ocr(let t): text = t
        default: return minW
        }
        let chars = CGFloat(text.count)
        let fontFactor = CGFloat(popupFontSize) / 13.0
        return min(700, max(minW, 200 + chars * fontFactor))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func languageOptions(current: String) -> [String] {
        var list = Languages.quickList
        if !list.contains(current) {
            list.insert(current, at: 0)
        }
        return list
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override var mouseDownCanMoveWindow: Bool { true }
}

private extension View {
    /// Custom delayed hover tooltip. SwiftUI's `.help(...)` relies on
    /// NSToolTipManager, which does not reliably show tooltips on the
    /// nonactivating floating popup panel (never becomes key window).
    func popupButtonHelp(_ text: String) -> some View {
        modifier(PopupButtonHelpModifier(text: text))
    }
}

private struct PopupButtonHelpModifier: ViewModifier {
    let text: String
    @State private var isHovering = false
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000) // 500 ms
                        guard !Task.isCancelled, isHovering else { return }
                        showTooltip = true
                    }
                } else {
                    showTooltip = false
                }
            }
            .overlay(alignment: .top) {
                if showTooltip {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .fixedSize()
                        .offset(y: -28)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.12), value: showTooltip)
    }
}

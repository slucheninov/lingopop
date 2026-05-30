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
        case .result(let result):
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: result.operation.systemImage)
                        .font(.system(size: headerFontSize, weight: .semibold))
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
                Button(action: { state.onReplace?(result.translated) }) {
                    Label("Replace", systemImage: "arrow.uturn.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button(action: { state.onRewrite?(result.translated) }) {
                    Label("Rewrite", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if result.operation != .explain {
                    Button(action: { state.onExplain?(result.translated) }) {
                        Label("Explain", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                if !state.availableRetryProviders.isEmpty {
                    Menu {
                        ForEach(state.availableRetryProviders, id: \.self) { provider in
                            Button("Retry with \(provider.rawValue)") {
                                state.onRetry?(provider)
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
        // Minimum must fit the header row; scales with header font size
        let minW = max(320, headerFontSize * 30)
        guard case .result(let result) = state.phase else { return minW }
        let chars = CGFloat(result.translated.count)
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

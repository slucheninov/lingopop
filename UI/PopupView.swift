import SwiftUI
import AppKit

struct PopupView: View {

    @ObservedObject var state: PopupState
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(14)
        .frame(width: 360, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 6)
    }

    @ViewBuilder
    private var content: some View {
        switch state.phase {
        case .loading(let preview):
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Translating…")
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
                Label {
                    Text("\(result.provider.rawValue)\(result.operation == .translate ? " → " + result.targetLanguage : "")")
                        .font(.system(size: 10, weight: .semibold))
                } icon: {
                    Image(systemName: result.operation.systemImage).font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                if result.viaFallback {
                    Text("fallback")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Button(action: { copy(result.translated) }) {
                    Label("Copy", systemImage: "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button(action: { state.onReplace?(result.translated) }) {
                    Label("Replace", systemImage: "arrow.uturn.left").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                if !state.availableRetryProviders.isEmpty {
                    Menu {
                        ForEach(state.availableRetryProviders, id: \.self) { provider in
                            Button("Retry with \(provider.rawValue)") {
                                state.onRetry?(provider)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                }
            }
            Text(result.translated)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .error(let message):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.red)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

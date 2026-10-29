import SwiftUI
import AppKit

/// Shared popup preferences (also used by Settings → Main).
enum PopupPrefs {
    static let fontSizeKey = "LingoPop.popupFontSize"
    static let defaultFontSize: Double = 13
}

struct WindowDragHandle: NSViewRepresentable {
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

extension View {
    /// Custom delayed hover tooltip. SwiftUI's `.help(...)` relies on
    /// NSToolTipManager, which does not reliably show tooltips on the
    /// nonactivating floating popup panel (never becomes key window).
    func popupButtonHelp(_ text: LocalizedStringKey) -> some View {
        modifier(PopupButtonHelpModifier(text: text))
    }
}

private struct PopupButtonHelpModifier: ViewModifier {
    let text: LocalizedStringKey
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
                        try? await Task.sleep(nanoseconds: PopupLayout.tooltipDelayNanoseconds)
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

/// Small bordered action button used throughout the popup (with hover tooltip).
struct PopupActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .popupButtonHelp(title)
    }
}

/// "Retry with <provider>" menu; renders nothing when no providers are available.
struct RetryMenu: View {
    @ObservedObject var state: PopupState

    var body: some View {
        if !state.availableRetryProviders.isEmpty {
            Menu {
                ForEach(state.availableRetryProviders, id: \.self) { provider in
                    Button {
                        state.actions?.retry(with: provider)
                    } label: {
                        Label("Retry with \(provider.displayName)", systemImage: provider.sfSymbol)
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
}

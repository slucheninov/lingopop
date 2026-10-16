import SwiftUI
import AppKit

struct HistoryView: View {

    @ObservedObject var store: TranslationHistoryStore
    @State private var query: String = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filtered: [TranslationHistoryEntry] {
        guard !trimmedQuery.isEmpty else { return store.entries }
        let q = trimmedQuery.lowercased()
        return store.entries.filter {
            $0.original.lowercased().contains(q) || $0.translated.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain)
                Spacer()
                if !store.entries.isEmpty {
                    Button(role: .destructive) {
                        store.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .padding(10)
            Divider()

            if store.entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .resizable().scaledToFit().frame(width: 36, height: 36)
                        .foregroundStyle(.secondary)
                    Text("No translations yet.")
                        .foregroundStyle(.secondary)
                    Text("Press your hotkey on selected text to translate.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Text("No matches for “\(trimmedQuery)”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered) { entry in
                        EntryRow(entry: entry, onDelete: { store.remove(entry) })
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

private struct EntryRow: View {
    let entry: TranslationHistoryEntry
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Label(entry.operation.shortName, systemImage: entry.operation.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if entry.operation == .translate {
                    if let source = entry.sourceLanguage {
                        badge("\(source) → \(entry.targetLanguage)")
                    } else {
                        badge(entry.targetLanguage)
                    }
                }
                badge(entry.provider.displayName)
                Spacer()
                Text(entry.timestamp, format: .dateTime.hour().minute().day().month().year())
                    .font(.caption2).foregroundStyle(.secondary)
                Menu {
                    Button("Copy original") { copy(entry.original) }
                    Button("Copy translation") { copy(entry.translated) }
                    Divider()
                    Button("Delete", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            Text(entry.original)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
            Text(entry.translated)
                .font(.system(size: 13))
                .lineLimit(6)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

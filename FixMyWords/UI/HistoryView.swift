import AppKit
import SwiftUI
import FixMyWordsCore

struct HistoryView: View {
    let store: HistoryStore
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search history", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(10)
                .accessibilityIdentifier("history.search")
            let entries = store.search(query)
            if entries.isEmpty {
                ContentUnavailableView(store.entries.isEmpty ? "No fixes yet" : "No matches",
                                       systemImage: "clock.arrow.circlepath")
            } else {
                List(entries) { entry in
                    EntryRow(entry: entry)
                }
                .accessibilityIdentifier("history.list")
            }
        }
        .frame(minWidth: 520, minHeight: 380)
    }
}

private struct EntryRow: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.commandName).font(.headline)
                Spacer()
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                    .foregroundStyle(.secondary)
            }
            labelled("Original", entry.original, id: "history.original")
            labelled("Result", entry.result, id: "history.result")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.entry")
    }

    private func labelled(_ label: String, _ text: String, id: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Text(verbatim: text).lineLimit(4).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(id)
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .accessibilityLabel("Copy \(label.lowercased())")
        }
    }
}

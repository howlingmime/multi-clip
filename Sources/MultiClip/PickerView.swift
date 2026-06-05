import SwiftUI

struct PickerView: View {
    let items: [String]
    let onConfirm: ([String], String) -> Void
    let onCancel: () -> Void

    @State private var selectionOrder: [Int] = []
    @State private var separator: String = "\n"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pick clips to paste")
                    .font(.headline)
                Text("Click in the order you want them pasted. Enter to paste, Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(selectionOrder.count) selected")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .padding(12)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(items.indices, id: \.self) { idx in
                    ClipRow(
                        text: items[idx],
                        order: selectionOrder.firstIndex(of: idx).map { $0 + 1 }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(idx) }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Picker("Join with", selection: $separator) {
                Text("Newline").tag("\n")
                Text("Space").tag(" ")
                Text("Comma + space").tag(", ")
                Text("Blank line").tag("\n\n")
                Text("Tab").tag("\t")
            }
            .pickerStyle(.menu)
            .frame(width: 260)

            Spacer()

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(action: confirm) {
                Text("Paste \(selectionOrder.count > 0 ? "(\(selectionOrder.count))" : "")")
                    .frame(minWidth: 60)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(selectionOrder.isEmpty)
        }
        .padding(12)
    }

    private func toggle(_ idx: Int) {
        if let pos = selectionOrder.firstIndex(of: idx) {
            selectionOrder.remove(at: pos)
        } else {
            selectionOrder.append(idx)
        }
    }

    private func confirm() {
        let chosen = selectionOrder.map { items[$0] }
        onConfirm(chosen, separator)
    }
}

private struct ClipRow: View {
    let text: String
    let order: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            badge
            Text(preview)
                .font(.system(.body))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(order == nil ? Color.secondary.opacity(0.08) : Color.accentColor.opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(order == nil ? Color.clear : Color.accentColor, lineWidth: 1)
        )
    }

    private var badge: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.5), lineWidth: 1.2)
                .frame(width: 24, height: 24)
            if let order {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                Text("\(order)")
                    .foregroundColor(.white)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 280 {
            return String(trimmed.prefix(280)) + "…"
        }
        return trimmed.isEmpty ? text : trimmed
    }
}

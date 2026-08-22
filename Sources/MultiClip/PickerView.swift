import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ClipFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case history = "History"
    case snippets = "Snippets"
    var id: String { rawValue }
}

/// Bridge between the AppDelegate-owned monitor and the picker. Publishing changes
/// lets pin / unpin / delete update the UI without closing and reopening the window.
final class PickerViewModel: ObservableObject {
    @Published var clips: [Clip]
    init(clips: [Clip]) { self.clips = clips }
}

struct SeparatorPreset: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
    let shortcut: KeyEquivalent?
}

struct PickerView: View {
    @ObservedObject var model: PickerViewModel
    let onConfirm: ([Clip], String) -> Void
    let onCancel: () -> Void
    let onDelete: (Clip) -> Void
    let onPinRequest: (Clip) -> Void
    let onUnpin: (Clip) -> Void
    let onRenameRequest: (Clip) -> Void
    let initialFilter: ClipFilter

    @State private var selectionOrder: [UUID] = []
    @State private var separator: String = "\n"
    @State private var query: String = ""
    @State private var filter: ClipFilter
    @State private var hoveredID: UUID?
    @State private var focusedChosenID: UUID?
    @FocusState private var searchFocused: Bool

    private let presets: [SeparatorPreset] = [
        SeparatorPreset(label: "Newline",     value: "\n",   shortcut: "0"),
        SeparatorPreset(label: "Comma+space", value: ", ",   shortcut: "1"),
        SeparatorPreset(label: "Blank line",  value: "\n\n", shortcut: "2"),
        SeparatorPreset(label: "Space",       value: " ",    shortcut: "3"),
        SeparatorPreset(label: "Pipe",        value: " | ",  shortcut: "4")
    ]

    init(
        model: PickerViewModel,
        initialFilter: ClipFilter = .all,
        onConfirm: @escaping ([Clip], String) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: @escaping (Clip) -> Void,
        onPinRequest: @escaping (Clip) -> Void,
        onUnpin: @escaping (Clip) -> Void,
        onRenameRequest: @escaping (Clip) -> Void
    ) {
        self.model = model
        self.initialFilter = initialFilter
        _filter = State(initialValue: initialFilter)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onPinRequest = onPinRequest
        self.onUnpin = onUnpin
        self.onRenameRequest = onRenameRequest
    }

    // MARK: - Derived

    private var visibleClips: [Clip] {
        let scoped: [Clip]
        switch filter {
        case .all: scoped = model.clips
        case .history: scoped = model.clips.filter { !$0.pinned }
        case .snippets: scoped = model.clips.filter { $0.pinned }
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return scoped.sorted { ($0.pinned ? 1 : 0, $0.capturedAt) > ($1.pinned ? 1 : 0, $1.capturedAt) }
        }
        let tokens = Self.tokenize(trimmed)
        return scoped.filter { clip in
            let hay = ((clip.name ?? "") + " " + clip.text).lowercased()
            return tokens.allSatisfy { hay.contains($0) }
        }
    }

    private var chosenClips: [Clip] {
        selectionOrder.compactMap { id in model.clips.first(where: { $0.id == id }) }
    }

    private var previewClip: Clip? {
        if let id = hoveredID, let c = model.clips.first(where: { $0.id == id }) { return c }
        if let id = focusedChosenID, let c = model.clips.first(where: { $0.id == id }) { return c }
        return chosenClips.last ?? visibleClips.first
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                list
                Divider()
                previewPane
                    .frame(width: 300)
            }
            Divider()
            chosenStrip
            Divider()
            footer
        }
        .frame(minWidth: 820, minHeight: 520)
        .onChange(of: model.clips) { newValue in
            // Drop stale selections after external deletes.
            let alive = Set(newValue.map(\.id))
            selectionOrder.removeAll { !alive.contains($0) }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pick clips to paste").font(.headline)
                    Text("Enter to paste · Esc to cancel · ⌘⇧← / ⌘⇧→ to reorder · ⌘1–4 for separators")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $filter) {
                    ForEach(ClipFilter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clips…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(visibleClips.count) shown · \(selectionOrder.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .task { searchFocused = true }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(visibleClips) { clip in
                    ClipRow(
                        clip: clip,
                        order: selectionOrder.firstIndex(of: clip.id).map { $0 + 1 },
                        hovered: hoveredID == clip.id,
                        onTap: { toggle(clip) },
                        onDelete: { onDelete(clip) },
                        onPin: { onPinRequest(clip) },
                        onUnpin: { onUnpin(clip) },
                        onRename: { onRenameRequest(clip) },
                        onHover: { isIn in hoveredID = isIn ? clip.id : (hoveredID == clip.id ? nil : hoveredID) }
                    )
                }
                if visibleClips.isEmpty {
                    Text(query.isEmpty ? "No clips yet." : "No matches for \"\(query)\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(24)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private var previewPane: some View {
        PreviewPane(clip: previewClip)
            .padding(12)
    }

    private var chosenStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Chosen order — drag or ⌘⇧← / ⌘⇧→")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if chosenClips.isEmpty {
                        Text("Click clips above to select them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    }
                    ForEach(Array(chosenClips.enumerated()), id: \.element.id) { (idx, clip) in
                        ChosenChip(
                            clip: clip,
                            index: idx + 1,
                            focused: focusedChosenID == clip.id,
                            onTap: { focusedChosenID = clip.id },
                            onRemove: { toggle(clip) },
                            onMoveLeft: { move(clip.id, by: -1) },
                            onMoveRight: { move(clip.id, by: 1) }
                        )
                        .onDrag {
                            focusedChosenID = clip.id
                            return NSItemProvider(object: clip.id.uuidString as NSString)
                        }
                        .onDrop(of: [UTType.plainText], delegate: ChosenDropDelegate(
                            target: clip.id,
                            order: $selectionOrder
                        ))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            presetButtons
            Spacer()
            reorderButtons
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

    private var presetButtons: some View {
        ForEach(presets) { preset in
            PresetButton(
                preset: preset,
                selected: separator == preset.value,
                onSelect: { separator = preset.value }
            )
        }
    }

    private var reorderButtons: some View {
        Group {
            Button("Move ←", action: { if let id = focusedChosenID { move(id, by: -1) } })
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                .disabled(focusedChosenID == nil)
            Button("Move →", action: { if let id = focusedChosenID { move(id, by: 1) } })
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                .disabled(focusedChosenID == nil)
        }
    }

    // MARK: - Actions

    private func toggle(_ clip: Clip) {
        if let pos = selectionOrder.firstIndex(of: clip.id) {
            selectionOrder.remove(at: pos)
            if focusedChosenID == clip.id { focusedChosenID = selectionOrder.last }
        } else {
            selectionOrder.append(clip.id)
            focusedChosenID = clip.id
        }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let from = selectionOrder.firstIndex(of: id) else { return }
        let to = max(0, min(selectionOrder.count - 1, from + delta))
        guard to != from else { return }
        selectionOrder.remove(at: from)
        selectionOrder.insert(id, at: to)
    }

    private func confirm() {
        onConfirm(chosenClips, separator)
    }

    private static func tokenize(_ q: String) -> [String] {
        q.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "/" || $0 == "." || $0 == "\\" || $0 == "_" || $0 == "-" }).map(String.init)
    }
}

// MARK: - Optional shortcut modifier

private struct OptionalShortcut: ViewModifier {
    let key: KeyEquivalent?
    let modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else {
            content
        }
    }
}

// MARK: - Preset button

private struct PresetButton: View {
    let preset: SeparatorPreset
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(preset.label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(background)
                .overlay(border)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .modifier(OptionalShortcut(key: preset.shortcut, modifiers: .command))
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.10))
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1)
    }

    private var helpText: String {
        if let ch = preset.shortcut?.character { return "\(preset.label) (⌘\(ch))" }
        return preset.label
    }
}

// MARK: - Row

private struct ClipRow: View {
    let clip: Clip
    let order: Int?
    let hovered: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void
    let onUnpin: () -> Void
    let onRename: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            badge
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    typeBadge
                    if clip.pinned {
                        Image(systemName: "pin.fill").foregroundStyle(.orange).font(.caption)
                        if let name = clip.name, !name.isEmpty {
                            Text(name).font(.caption.bold())
                        }
                    }
                    Spacer()
                }
                Text(previewText)
                    .font(.system(.body))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            deleteButton
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(order == nil
                      ? (hovered ? Color.secondary.opacity(0.14) : Color.secondary.opacity(0.08))
                      : Color.accentColor.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(order == nil ? Color.clear : Color.accentColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover(perform: onHover)
        .contextMenu {
            if clip.pinned {
                Button("Rename Snippet…", action: onRename)
                Button("Unpin", action: onUnpin)
            } else {
                Button("Pin as Snippet…", action: onPin)
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var badge: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1.2).frame(width: 24, height: 24)
            if let order {
                Circle().fill(Color.accentColor).frame(width: 24, height: 24)
                Text("\(order)").foregroundColor(.white).font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private var typeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: clip.kind.symbolName).font(.caption2)
            Text(clip.kind.badge).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Color.secondary.opacity(0.18))
        )
        .foregroundStyle(.secondary)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .opacity(hovered ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .help("Delete from history")
    }

    private var previewText: String {
        let trimmed = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 280 { return String(trimmed.prefix(280)) + "…" }
        return trimmed.isEmpty ? clip.text : trimmed
    }
}

// MARK: - Chosen chip

private struct ChosenChip: View {
    let clip: Clip
    let index: Int
    let focused: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    let onMoveLeft: () -> Void
    let onMoveRight: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onMoveLeft) { Image(systemName: "chevron.left").font(.caption2) }
                .buttonStyle(.plain)
                .help("Move left")
            ZStack {
                Circle().fill(Color.accentColor).frame(width: 18, height: 18)
                Text("\(index)").foregroundColor(.white).font(.system(size: 10, weight: .semibold))
            }
            Text(shortPreview).font(.caption).lineLimit(1)
            Button(action: onMoveRight) { Image(systemName: "chevron.right").font(.caption2) }
                .buttonStyle(.plain)
                .help("Move right")
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.caption) }
                .buttonStyle(.plain)
                .help("Deselect")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(focused ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var shortPreview: String {
        let flat = clip.text.replacingOccurrences(of: "\n", with: " ")
        if flat.count > 24 { return String(flat.prefix(24)) + "…" }
        return flat.isEmpty ? clip.kind.badge : flat
    }
}

// MARK: - Drop delegate (reorder)

private struct ChosenDropDelegate: DropDelegate {
    let target: UUID
    @Binding var order: [UUID]

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [UTType.plainText]).first else { return false }
        item.loadObject(ofClass: NSString.self) { obj, _ in
            DispatchQueue.main.async {
                guard let str = obj as? String, let sourceID = UUID(uuidString: str) else { return }
                guard let from = order.firstIndex(of: sourceID),
                      let to = order.firstIndex(of: target),
                      from != to else { return }
                let moved = order.remove(at: from)
                order.insert(moved, at: to)
            }
        }
        return true
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }
}

// MARK: - Preview pane

private struct PreviewPane: View {
    let clip: Clip?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let clip {
                header(clip)
                Divider()
                content(clip)
                Spacer(minLength: 0)
            } else {
                Text("Hover a clip to preview it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: clip.kind.symbolName)
                Text(clip.displayTitle).font(.headline)
                Spacer()
                if clip.pinned {
                    Image(systemName: "pin.fill").foregroundStyle(.orange)
                }
            }
            Text(clip.capturedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func content(_ clip: Clip) -> some View {
        switch clip.kind {
        case .image:
            if let data = clip.data, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .cornerRadius(6)
                Text("\(Int(img.size.width))×\(Int(img.size.height)) · \(data.count) bytes")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Image data unavailable").foregroundStyle(.secondary)
            }
        case .color:
            if let data = clip.data,
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: color))
                    .frame(height: 80)
            }
            Text(clip.text).font(.system(.body, design: .monospaced))
        case .fileURL:
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(clip.fileURLs ?? [], id: \.self) { s in
                        if let url = URL(string: s) {
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 22, height: 22)
                                Text(url.path).font(.caption).lineLimit(2)
                            }
                        }
                    }
                }
            }
        case .text, .rtf, .html:
            ScrollView {
                Text(clip.text)
                    .font(.system(.body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}

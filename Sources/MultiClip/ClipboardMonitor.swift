import AppKit

final class ClipboardMonitor {
    private(set) var clips: [Clip] = []
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let historyCap: Int
    private var store: ClipStore

    var onChange: (() -> Void)?

    init(store: ClipStore, historyCap: Int = 50) {
        self.store = store
        self.historyCap = historyCap
    }

    func start() {
        clips = store.loadAll()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Swap the persistence backing (e.g. after enabling encrypted storage). Existing
    /// in-memory clips are written to the new store; the caller is responsible for
    /// tearing down the old one.
    func swapStore(_ newStore: ClipStore, migrateExisting: Bool) {
        store = newStore
        if migrateExisting {
            for clip in clips { store.upsert(clip) }
        } else {
            clips = store.loadAll()
        }
        onChange?()
    }

    // MARK: - Public mutations

    func clear() {
        // Keep pinned snippets — clearing the "history" only affects transient clips.
        let kept = clips.filter { $0.pinned }
        let removed = clips.filter { !$0.pinned }
        clips = kept
        for c in removed { store.delete(id: c.id) }
        onChange?()
    }

    func clearEverything() {
        clips.removeAll()
        store.clear()
        onChange?()
    }

    func delete(id: UUID) {
        clips.removeAll { $0.id == id }
        store.delete(id: id)
        onChange?()
    }

    func pin(id: UUID, name: String) {
        guard let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[idx].pinned = true
        clips[idx].name = name
        store.upsert(clips[idx])
        onChange?()
    }

    func unpin(id: UUID) {
        guard let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[idx].pinned = false
        clips[idx].name = nil
        store.upsert(clips[idx])
        onChange?()
    }

    func rename(id: UUID, name: String) {
        guard let idx = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[idx].name = name.isEmpty ? nil : name
        store.upsert(clips[idx])
        onChange?()
    }

    // MARK: - Poll

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let clip = readClip(from: pb) else { return }
        ingest(clip)
    }

    private func ingest(_ new: Clip) {
        // Dedupe by content — promote existing entry to the top.
        if let idx = clips.firstIndex(where: { $0.contentSignature == new.contentSignature }) {
            var existing = clips.remove(at: idx)
            existing.capturedAt = Date()
            clips.insert(existing, at: 0)
            store.upsert(existing)
        } else {
            clips.insert(new, at: 0)
            store.upsert(new)
        }
        evict()
        onChange?()
    }

    private func evict() {
        let unpinned = clips.enumerated().filter { !$0.element.pinned }
        guard unpinned.count > historyCap else { return }
        let dropIndices = unpinned.suffix(unpinned.count - historyCap).map { $0.offset }
        for i in dropIndices.sorted(by: >) {
            let removed = clips.remove(at: i)
            store.delete(id: removed.id)
        }
    }

    // MARK: - Read pasteboard flavors

    private func readClip(from pb: NSPasteboard) -> Clip? {
        let types = Set(pb.types ?? [])

        // File URLs (may be multiple items).
        if types.contains(.fileURL) {
            if let objs = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !objs.isEmpty {
                let strings = objs.map { $0.path }
                return Clip(kind: .fileURL, text: strings.joined(separator: "\n"), fileURLs: objs.map { $0.absoluteString })
            }
        }

        // Image: prefer PNG for storage; fall back to TIFF.
        if types.contains(.png), let data = pb.data(forType: .png) {
            return Clip(kind: .image, text: "Image (PNG · \(data.count) bytes)", data: data)
        }
        if types.contains(.tiff), let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            return Clip(kind: .image, text: "Image (\(png.count) bytes)", data: png)
        }

        // Color (archived NSColor).
        if types.contains(.color),
           let colorData = pb.data(forType: .color),
           let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            let r = Int((color.redComponent * 255).rounded())
            let g = Int((color.greenComponent * 255).rounded())
            let b = Int((color.blueComponent * 255).rounded())
            let label = String(format: "#%02X%02X%02X  (r%d g%d b%d)", r, g, b, r, g, b)
            return Clip(kind: .color, text: label, data: colorData)
        }

        // RTF (with plain-text extraction for preview + search).
        if types.contains(.rtf), let data = pb.data(forType: .rtf) {
            let plain = (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))?.string ?? ""
            let preview = plain.isEmpty ? (pb.string(forType: .string) ?? "") : plain
            return Clip(kind: .rtf, text: preview, data: data)
        }

        // HTML (with plain-text extraction).
        if types.contains(.html), let data = pb.data(forType: .html) {
            let plain = (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil))?.string ?? ""
            let preview = plain.isEmpty ? (pb.string(forType: .string) ?? String(data: data, encoding: .utf8) ?? "") : plain
            return Clip(kind: .html, text: preview, data: data)
        }

        // Plain text.
        if let s = pb.string(forType: .string), !s.isEmpty {
            return Clip(kind: .text, text: s)
        }

        return nil
    }
}

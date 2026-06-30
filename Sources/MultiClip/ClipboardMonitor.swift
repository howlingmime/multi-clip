import AppKit

final class ClipboardMonitor {
    private(set) var items: [String] = []
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let maxItems = 50
    private let storeURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MultiClip", isDirectory: true)
            .appendingPathComponent("history.json")
    }()

    func start() {
        load()
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func clear() {
        items.removeAll()
        save()
    }

    func delete(_ value: String) {
        guard let idx = items.firstIndex(of: value) else { return }
        items.remove(at: idx)
        save()
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let str = pb.string(forType: .string), !str.isEmpty else { return }
        if let idx = items.firstIndex(of: str) {
            items.remove(at: idx)
        }
        items.insert(str, at: 0)
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        items = Array(decoded.prefix(maxItems))
    }

    private func save() {
        let dir = storeURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

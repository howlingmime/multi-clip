import AppKit

final class ClipboardMonitor {
    private(set) var items: [String] = []
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let maxItems = 50

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func clear() {
        items.removeAll()
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
    }
}

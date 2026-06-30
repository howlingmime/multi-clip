import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let clipboardMonitor = ClipboardMonitor()
    private var hotKey: HotKey?
    private var pickerWindow: NSWindow?
    private weak var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        clipboardMonitor.start()
        hotKey = HotKey(keyCode: 35, modifiers: [.command, .shift]) { [weak self] in
            self?.showPicker()
        }
        promptForAccessibilityIfNeeded()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "📋"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Show Picker  ⇧⌘P", action: #selector(showPickerFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MultiClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != nil && item.target == nil {
            if item.action != #selector(NSApplication.terminate(_:)) {
                item.target = self
            }
        }
        statusItem.menu = menu
    }

    @objc private func showPickerFromMenu() { showPicker() }
    @objc private func clearHistory() { clipboardMonitor.clear() }

    private func showPicker() {
        if let existing = pickerWindow {
            existing.close()
            pickerWindow = nil
        }

        previousApp = NSWorkspace.shared.frontmostApplication

        let items = clipboardMonitor.items
        if items.isEmpty {
            NSSound.beep()
            return
        }

        let view = PickerView(
            items: items,
            onConfirm: { [weak self] chosen, separator in
                self?.closePicker()
                self?.paste(chosen.joined(separator: separator))
            },
            onCancel: { [weak self] in
                self?.closePicker()
            },
            onDelete: { [weak self] value in
                self?.clipboardMonitor.delete(value)
            }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "MultiClip — pick clips to paste"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.setContentSize(NSSize(width: 560, height: 480))
        window.center()
        window.isReleasedWhenClosed = false

        pickerWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closePicker() {
        pickerWindow?.close()
        pickerWindow = nil
    }

    private func paste(_ text: String) {
        guard !text.isEmpty else { return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        if let app = previousApp {
            app.activate(options: [])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            sendCommandV()
        }
    }

    private func promptForAccessibilityIfNeeded() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

private func sendCommandV() {
    let source = CGEventSource(stateID: .combinedSessionState)
    let vKey: CGKeyCode = 9
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
        return
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

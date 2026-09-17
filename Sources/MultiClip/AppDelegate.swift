import AppKit
import SwiftUI
import ApplicationServices
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var clipboardMonitor: ClipboardMonitor!
    private var pickerModel: PickerViewModel?
    private var hotKeyPicker: HotKey?
    private var hotKeySnippets: HotKey?
    private var pickerWindow: NSWindow?
    private weak var previousApp: NSRunningApplication?

    private let encryptedKey = "MultiClipEncryptedEnabled"
    private let keychainAccount = "primary"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = initialStore()
        clipboardMonitor = ClipboardMonitor(store: store, historyCap: currentHistoryCap())
        clipboardMonitor.onChange = { [weak self] in
            self?.pickerModel?.clips = self?.clipboardMonitor.clips ?? []
        }
        clipboardMonitor.start()

        setupStatusItem()
        hotKeyPicker = HotKey(keyCode: 35, modifiers: [.command, .shift]) { [weak self] in
            self?.showPicker(filter: .all)
        }
        hotKeySnippets = HotKey(keyCode: 1, modifiers: [.command, .shift]) { [weak self] in
            self?.showPicker(filter: .snippets)
        }
        promptForAccessibilityIfNeeded()
    }

    /// Encrypted persistence is the "keep everything" mode, so it lifts the rolling cap.
    private func currentHistoryCap() -> Int {
        UserDefaults.standard.bool(forKey: encryptedKey) ? HistoryCap.persistent : HistoryCap.rolling
    }

    private func initialStore() -> ClipStore {
        if UserDefaults.standard.bool(forKey: encryptedKey),
           let passphrase = Keychain.passphrase(account: keychainAccount),
           let sqlite = try? SQLiteClipStore(passphrase: passphrase) {
            return sqlite
        }
        // Fall back to unencrypted file if encrypted mode was on but the keychain read failed.
        UserDefaults.standard.set(false, forKey: encryptedKey)
        return FileClipStore()
    }

    // MARK: - Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button { button.title = "📋" }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        add(menu, "Show Picker  ⇧⌘P", #selector(showPickerFromMenu))
        add(menu, "Show Snippets  ⇧⌘S", #selector(showSnippetsFromMenu))
        menu.addItem(.separator())
        add(menu, "Save History…", #selector(saveHistory))
        add(menu, "Clear History", #selector(clearHistory))
        menu.addItem(.separator())
        let encTitle = UserDefaults.standard.bool(forKey: encryptedKey)
            ? "Disable Encrypted Persistent History"
            : "Enable Encrypted Persistent History…"
        add(menu, encTitle, #selector(toggleEncryptedStorage))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MultiClip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    // MARK: - Menu actions

    @objc private func showPickerFromMenu() { showPicker(filter: .all) }
    @objc private func showSnippetsFromMenu() { showPicker(filter: .snippets) }
    @objc private func clearHistory() { clipboardMonitor.clear() }

    @objc private func saveHistory() {
        let clips = clipboardMonitor.clips
        guard !clips.isEmpty else { NSSound.beep(); return }

        let panel = NSSavePanel()
        panel.title = "Save Clipboard History"
        panel.nameFieldStringValue = "MultiClip-history.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let text = clips.map { $0.text }.joined(separator: "\n\n")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't save history"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func toggleEncryptedStorage() {
        let currentlyOn = UserDefaults.standard.bool(forKey: encryptedKey)
        NSApp.activate(ignoringOtherApps: true)
        if currentlyOn {
            let alert = NSAlert()
            alert.messageText = "Disable encrypted persistent history?"
            alert.informativeText = "Your encrypted database will be deleted. Non-encrypted history storage resumes, and history is trimmed back to the most recent \(HistoryCap.rolling) unpinned clips. Pinned snippets are kept."
            alert.addButton(withTitle: "Disable")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            Keychain.deletePassphrase(account: keychainAccount)
            try? FileManager.default.removeItem(at: StorePaths.sqliteURL)
            UserDefaults.standard.set(false, forKey: encryptedKey)
            clipboardMonitor.swapStore(FileClipStore(), migrateExisting: true)
            clipboardMonitor.setHistoryCap(HistoryCap.rolling)
        } else {
            guard let passphrase = promptForPassphrase() else { return }
            do {
                let sqlite = try SQLiteClipStore(passphrase: passphrase)
                Keychain.setPassphrase(passphrase, account: keychainAccount)
                UserDefaults.standard.set(true, forKey: encryptedKey)
                // Raise the cap before migrating so nothing is evicted on the way across.
                clipboardMonitor.setHistoryCap(HistoryCap.persistent)
                clipboardMonitor.swapStore(sqlite, migrateExisting: true)
                // The JSON history is plaintext on disk; leaving it behind would defeat
                // the point of switching to an encrypted store.
                try? FileManager.default.removeItem(at: StorePaths.jsonHistoryURL)
            } catch {
                let a = NSAlert(); a.messageText = "Could not initialize encrypted store"
                a.informativeText = error.localizedDescription; a.alertStyle = .warning; a.runModal()
                return
            }
        }
        rebuildMenu()
    }

    private func promptForPassphrase() -> String? {
        let alert = NSAlert()
        alert.messageText = "Set encryption passphrase"
        alert.informativeText = "Clips will be encrypted at rest using AES-GCM with a key derived from this passphrase, and history survives reboots and grows to \(HistoryCap.persistent) clips instead of \(HistoryCap.rolling). The passphrase is stored in your macOS Keychain, and the existing plaintext history file is deleted."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Passphrase (min 6 chars)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue
        return v.count >= 6 ? v : nil
    }

    // MARK: - Picker

    private func showPicker(filter: ClipFilter) {
        if pickerWindow != nil { closePicker() }
        previousApp = NSWorkspace.shared.frontmostApplication

        let clips = clipboardMonitor.clips
        if clips.isEmpty { NSSound.beep(); return }

        let model = PickerViewModel(clips: clips)
        pickerModel = model

        let view = PickerView(
            model: model,
            initialFilter: filter,
            onConfirm: { [weak self] chosen, sep in
                self?.closePicker()
                self?.paste(chosen, separator: sep)
            },
            onCancel: { [weak self] in self?.closePicker() },
            onDelete: { [weak self] clip in self?.clipboardMonitor.delete(id: clip.id) },
            onPinRequest: { [weak self] clip in self?.promptPin(clip) },
            onUnpin: { [weak self] clip in self?.clipboardMonitor.unpin(id: clip.id) },
            onRenameRequest: { [weak self] clip in self?.promptRename(clip) }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "MultiClip — pick clips to paste"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.setContentSize(NSSize(width: 860, height: 560))
        window.center()
        window.isReleasedWhenClosed = false

        pickerWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func closePicker() {
        pickerWindow?.close()
        pickerWindow = nil
        pickerModel = nil
    }

    private func promptPin(_ clip: Clip) {
        let alert = NSAlert()
        alert.messageText = "Name this snippet"
        alert.informativeText = "Pinned snippets never expire and appear in the Snippets filter."
        alert.addButton(withTitle: "Pin")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultSnippetName(for: clip)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        clipboardMonitor.pin(id: clip.id, name: name.isEmpty ? defaultSnippetName(for: clip) : name)
    }

    private func promptRename(_ clip: Clip) {
        let alert = NSAlert()
        alert.messageText = "Rename snippet"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = clip.name ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clipboardMonitor.rename(id: clip.id, name: field.stringValue.trimmingCharacters(in: .whitespaces))
    }

    private func defaultSnippetName(for clip: Clip) -> String {
        let flat = clip.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return String(flat.prefix(32))
    }

    // MARK: - Paste

    private func paste(_ clips: [Clip], separator: String) {
        guard !clips.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()

        if clips.count == 1, let single = clips.first {
            write(single, to: pb)
        } else {
            let joined = clips.map { $0.text }.joined(separator: separator)
            pb.setString(joined, forType: .string)
        }

        if let app = previousApp { app.activate(options: []) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { sendCommandV() }
    }

    private func write(_ clip: Clip, to pb: NSPasteboard) {
        switch clip.kind {
        case .text:
            pb.setString(clip.text, forType: .string)
        case .rtf:
            if let data = clip.data { pb.setData(data, forType: .rtf) }
            pb.setString(clip.text, forType: .string)
        case .html:
            if let data = clip.data { pb.setData(data, forType: .html) }
            pb.setString(clip.text, forType: .string)
        case .image:
            if let data = clip.data, let img = NSImage(data: data) {
                pb.writeObjects([img])
            } else {
                pb.setString(clip.text, forType: .string)
            }
        case .fileURL:
            let urls = (clip.fileURLs ?? []).compactMap(URL.init(string:))
            if !urls.isEmpty {
                pb.writeObjects(urls as [NSPasteboardWriting])
            } else {
                pb.setString(clip.text, forType: .string)
            }
        case .color:
            if let data = clip.data,
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                pb.writeObjects([color])
            } else {
                pb.setString(clip.text, forType: .string)
            }
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

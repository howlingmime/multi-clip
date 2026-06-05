import AppKit
import Carbon.HIToolbox

struct CarbonModifiers: OptionSet {
    let rawValue: UInt32
    static let command = CarbonModifiers(rawValue: UInt32(cmdKey))
    static let shift   = CarbonModifiers(rawValue: UInt32(shiftKey))
    static let option  = CarbonModifiers(rawValue: UInt32(optionKey))
    static let control = CarbonModifiers(rawValue: UInt32(controlKey))
}

final class HotKey {
    private static var nextID: UInt32 = 1
    private static var registry: [UInt32: HotKey] = [:]
    private static var handlerInstalled = false

    private let id: UInt32
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?

    init(keyCode: UInt32, modifiers: CarbonModifiers, action: @escaping () -> Void) {
        self.id = HotKey.nextID
        HotKey.nextID += 1
        self.action = action
        HotKey.registry[id] = self

        HotKey.installHandlerIfNeeded()

        let signature: OSType = 0x4D434C50 // 'MCLP'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        HotKey.registry.removeValue(forKey: id)
    }

    fileprivate func fire() { action() }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, _) -> OSStatus in
                guard let eventRef else { return noErr }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status == noErr, let hk = HotKey.registry[hkID.id] {
                    DispatchQueue.main.async { hk.fire() }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )
    }
}

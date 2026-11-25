import Carbon
import Foundation
import HoltCore

private func holtHotKeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard err == noErr else { return err }
    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            GlobalHotkeys.shared.trigger(rawID: id)
        }
    }
    return noErr
}

/// Global keyboard shortcuts via Carbon `RegisterEventHotKey` (requires no Accessibility permission).
@MainActor
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    private enum HotKeyActionID: UInt32 {
        case startPause = 1
        case takeBreak = 2
        case endSession = 3
    }

    private static let signature: OSType = 0x484F_4C54 // 'HOLT'
    private var handlerRef: EventHandlerRef?
    private var registeredRefs: [EventHotKeyRef] = []

    func configure(with settings: AppSettings) {
        unregisterAll()
        guard settings.hotkeysEnabled else { return }
        installHandlerIfNeeded()

        register(shortcut: settings.startPauseHotkey, id: .startPause)
        register(shortcut: settings.breakHotkey, id: .takeBreak)
        register(shortcut: settings.endHotkey, id: .endSession)
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            holtHotKeyCallback,
            1,
            &spec,
            nil,
            &handlerRef
        )
        if status != noErr {
            Diagnostics.log("Failed to install global hotkey handler: \(status)")
        }
    }

    private func register(shortcut: HotkeyShortcut, id: HotKeyActionID) {
        guard shortcut.isEnabled else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            registeredRefs.append(ref)
        } else {
            Diagnostics.log("Failed to register hotkey \(shortcut.displayString): \(status)")
        }
    }

    private func unregisterAll() {
        for ref in registeredRefs {
            UnregisterEventHotKey(ref)
        }
        registeredRefs.removeAll()
    }

    fileprivate func trigger(rawID: UInt32) {
        guard let action = HotKeyActionID(rawValue: rawID) else { return }
        let model = AppModel.shared
        switch action {
        case .startPause:
            model.toggleStartPauseFromHotkey()
        case .takeBreak:
            model.perform(.takeBreak)
        case .endSession:
            switch model.state.phase {
            case .running(let kind, _, _, _) where kind.isBreak:
                model.perform(.endBreak)
            default:
                model.perform(.endSession)
            }
        }
    }
}

import Carbon
import Foundation
import TodoPinCore

enum HotKeyServiceError: LocalizedError {
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "快捷键注册失败，系统返回 \(status)。"
        }
    }
}

struct HotKeyRegistration {
    let id: UInt32
    let shortcut: HotKeyShortcut
    let onTrigger: () -> Void
}

final class HotKeyService {
    private var callbacks: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    deinit {
        unregister()
    }

    func register(_ registrations: [HotKeyRegistration]) throws {
        unregister()
        guard !registrations.isEmpty else {
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }
                let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                guard let event,
                      let id = service.hotKeyID(from: event) else {
                    return noErr
                }
                DispatchQueue.main.async {
                    service.callbacks[id]?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            throw HotKeyServiceError.registrationFailed(handlerStatus)
        }

        for registration in registrations {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: registration.id)
            let status = RegisterEventHotKey(
                registration.shortcut.keyCode,
                registration.shortcut.modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )

            guard status == noErr, let hotKeyRef else {
                unregister()
                throw HotKeyServiceError.registrationFailed(status)
            }

            hotKeyRefs[registration.id] = hotKeyRef
            callbacks[registration.id] = registration.onTrigger
        }
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        callbacks.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func hotKeyID(from event: EventRef) -> UInt32? {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == Self.signature else {
            return nil
        }
        return hotKeyID.id
    }

    private static let signature: OSType = {
        let scalars = Array("TDPn".unicodeScalars).map { OSType($0.value) }
        return scalars.reduce(0) { ($0 << 8) + $1 }
    }()
}

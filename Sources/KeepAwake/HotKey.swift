import AppKit
import Combine
import Carbon.HIToolbox

@MainActor
final class HotKey: ObservableObject {
    static let displayName = "⌃⌥⌘K"
    static let visibilityDisplayName = "⌃⌥⌘H"

    private static let defaultsKey = "hotKeyEnabled"

    private static let signature: OSType = 0x4B41_574B

    private static let modifiers =
        UInt32(controlKey | optionKey | cmdKey)

    private static let sleepHotKeyID: UInt32 = 1
    private static let visibilityHotKeyID: UInt32 = 2

    @Published var isEnabled =
        (UserDefaults.standard.object(
            forKey: HotKey.defaultsKey
        ) as? Bool) ?? true {
        didSet {
            guard oldValue != isEnabled else {
                return
            }

            UserDefaults.standard.set(
                isEnabled,
                forKey: Self.defaultsKey
            )

            if isEnabled {
                registerSleepHotKey()
            } else {
                unregisterSleepHotKey()
            }
        }
    }

    @Published private(set) var isVisibilityRegistered = false

    @Published private(set) var registrationError: String?

    private let sleepManager: SleepManager
    private let visibilityManager: VisibilityManager

    private var sleepHotKeyRef: EventHotKeyRef?
    private var visibilityHotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(
        sleepManager: SleepManager,
        visibilityManager: VisibilityManager
    ) {
        self.sleepManager = sleepManager
        self.visibilityManager = visibilityManager

        installHandler()

        if isEnabled {
            registerSleepHotKey()
        }

        registerVisibilityHotKey()
    }

    // MARK: - Handle shortcuts

    private func handlePress(_ id: UInt32) {
        switch id {
        case Self.sleepHotKeyID:
            sleepManager.toggle()

        case Self.visibilityHotKeyID:
            visibilityManager.toggle()

        default:
            break
        }
    }

    // MARK: - Carbon event handler

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = Unmanaged
            .passUnretained(self)
            .toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event,
                      let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID(
                    signature: 0,
                    id: 0
                )

                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard result == noErr else {
                    return result
                }

                guard hotKeyID.signature == 0x4B41_574B else {
                    return OSStatus(eventNotHandledErr)
                }

                let id = hotKeyID.id

                guard id == 1 || id == 2 else {
                    return OSStatus(eventNotHandledErr)
                }

                let hotKey = Unmanaged<HotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                Task { @MainActor in
                    hotKey.handlePress(id)
                }

                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )

        if status != noErr {
            registrationError =
                "Unable to install keyboard shortcut handler."

            NSLog(
                "KeepAwake: hotkey handler error \(status)"
            )
        }
    }

    // MARK: - Sleep shortcut

    private func registerSleepHotKey() {
        guard sleepHotKeyRef == nil,
              handlerRef != nil else {
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.sleepHotKeyID
        )

        var newRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            Self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        if status == noErr {
            sleepHotKeyRef = newRef
        } else {
            NSLog(
                "KeepAwake: sleep hotkey error \(status)"
            )
        }
    }

    private func unregisterSleepHotKey() {
        guard let sleepHotKeyRef else {
            return
        }

        UnregisterEventHotKey(sleepHotKeyRef)
        self.sleepHotKeyRef = nil
    }

    // MARK: - Visibility shortcut

    private func registerVisibilityHotKey() {
        guard visibilityHotKeyRef == nil else {
            return
        }

        guard handlerRef != nil else {
            visibilityManager.setRecoveryAvailable(false)
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.visibilityHotKeyID
        )

        var newRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_H),
            Self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )

        if status == noErr, let newRef {
            visibilityHotKeyRef = newRef

            isVisibilityRegistered = true
            registrationError = nil

            visibilityManager.setRecoveryAvailable(true)
        } else {
            isVisibilityRegistered = false

            registrationError =
                "The visibility shortcut is unavailable. " +
                "Another application may be using it."

            visibilityManager.setRecoveryAvailable(false)

            NSLog(
                "KeepAwake: visibility hotkey error \(status)"
            )
        }
    }

    func retryVisibilityRegistration() {
        registerVisibilityHotKey()
    }
}
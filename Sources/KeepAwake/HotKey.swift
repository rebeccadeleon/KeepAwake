import AppKit
import Carbon.HIToolbox

/// Registers a system-wide keyboard shortcut that toggles Keep Awake.
@MainActor
final class HotKey: ObservableObject {
    /// How the shortcut is shown in the menu.
    static let displayName = "⌃⌥⌘K"

    private static let defaultsKey = "hotKeyEnabled"
    private static let keyCode = UInt32(kVK_ANSI_K)
    private static let modifiers = UInt32(controlKey | optionKey | cmdKey)

    /// Whether the shortcut is switched on. Defaults to on.
    @Published var isEnabled =
        (UserDefaults.standard.object(forKey: HotKey.defaultsKey) as? Bool) ?? true {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            if isEnabled {
                register()
            } else {
                unregister()
            }
        }
    }

    private let sleepManager: SleepManager
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(sleepManager: SleepManager) {
        self.sleepManager = sleepManager
        installHandler()
        if isEnabled {
            register()
        }
    }

    /// Called when the shortcut is pressed.
    private func handlePress() {
        if sleepManager.isManualActive {
            sleepManager.deactivate()
        } else {
            sleepManager.activate()
        }
    }

    /// Tells the system to call us when any of this app's hot keys is pressed.
    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    hotKey.handlePress()
                }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &handlerRef
        )
        if status != noErr {
            NSLog("KeepAwake: could not install hot key handler (error \(status))")
        }
    }

    private func register() {
        guard hotKeyRef == nil else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4B41_574B), id: 1)   // "KAWK"
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &newRef
        )
        if status == noErr {
            hotKeyRef = newRef
        } else {
            NSLog("KeepAwake: could not register \(Self.displayName) (error \(status)). Another app may be using it.")
        }
    }

    private func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}
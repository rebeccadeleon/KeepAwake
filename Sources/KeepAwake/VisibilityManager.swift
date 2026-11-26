import AppKit
import Combine

@MainActor
final class VisibilityManager: ObservableObject {
    static let shortcutName = "⌃⌥⌘H"

    private static let dockKey = "showInDock"
    private static let menuBarKey = "showInMenuBar"

    @Published private(set) var showInDock: Bool
    @Published private(set) var showInMenuBar: Bool

    @Published private(set) var isHidden = false
    @Published private(set) var recoveryAvailable = false
    @Published private(set) var visibilityError: String?
    @Published var startHidden: Bool =
        UserDefaults.standard.bool(forKey: "startHidden") {
        didSet {
            UserDefaults.standard.set(
                startHidden,
                forKey: "startHidden"
            )
        }
    }

    var onVisibilityChanged: (() -> Void)?

    init() {
        let defaults = UserDefaults.standard

        showInDock = defaults.object(
            forKey: Self.dockKey
        ) as? Bool ?? false

        showInMenuBar = defaults.object(
            forKey: Self.menuBarKey
        ) as? Bool ?? true

        // Always restore access after relaunch.
        if !showInDock && !showInMenuBar {
            showInMenuBar = true
        }
    }

    var isDockVisible: Bool {
        showInDock && !isHidden
    }

    var isMenuBarVisible: Bool {
        showInMenuBar && !isHidden
    }

    var canHide: Bool {
        recoveryAvailable
    }

    // MARK: - Preferences

    func setShowInDock(_ visible: Bool) {
        visibilityError = nil

        guard visible ||
              showInMenuBar ||
              recoveryAvailable else {
            reportRecoveryError()
            return
        }

        showInDock = visible

        savePreferences()
        applyVisibility()
    }

    func setShowInMenuBar(_ visible: Bool) {
        visibilityError = nil

        guard visible ||
              showInDock ||
              recoveryAvailable else {
            reportRecoveryError()
            return
        }

        showInMenuBar = visible

        savePreferences()
        applyVisibility()
    }

    // MARK: - Hide / Show

    func hide() {
        guard recoveryAvailable else {
            reportRecoveryError()
            return
        }

        guard !isHidden else {
            return
        }

        visibilityError = nil
        isHidden = true

        applyVisibility()
    }

    func show() {
        visibilityError = nil

        if !showInDock && !showInMenuBar {
            showInMenuBar = true
            savePreferences()
        }

        isHidden = false

        applyVisibility()
    }

    func toggle() {
        if isHidden ||
           (!isDockVisible && !isMenuBarVisible) {
            show()
        } else {
            hide()
        }
    }

    // MARK: - Recovery

    func setRecoveryAvailable(_ available: Bool) {
        recoveryAvailable = available

        if !available {
            isHidden = false

            if !showInDock && !showInMenuBar {
                showInMenuBar = true
                savePreferences()
            }
        }

        applyVisibility()
    }

    // MARK: - Visibility update

    func applyVisibility() {
        onVisibilityChanged?()
    }

    private func savePreferences() {
        UserDefaults.standard.set(
            showInDock,
            forKey: Self.dockKey
        )

        UserDefaults.standard.set(
            showInMenuBar,
            forKey: Self.menuBarKey
        )
    }

    private func reportRecoveryError() {
        visibilityError =
            "Recovery shortcut unavailable. " +
            "Keep at least one icon visible."
    }
}
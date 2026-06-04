import Foundation
import KeyboardShortcuts

// MARK: - Keyboard Shortcut Names

extension KeyboardShortcuts.Name {
    /// Toggle the HermesChat floating panel
    static let togglePanel = Self(
        "togglePanel",
        default: KeyboardShortcuts.Shortcut(.l, modifiers: [.command, .option])
    )

    /// Toggle between Stateless and Memory chat modes
    static let toggleMode = Self(
        "toggleMode",
        default: KeyboardShortcuts.Shortcut(.m, modifiers: [.command, .option])
    )

    /// Start a new conversation (clear current)
    static let newChat = Self(
        "newChat",
        default: KeyboardShortcuts.Shortcut(.n, modifiers: [.command, .option])
    )
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the user triggers the mode toggle shortcut
    static let hermesToggleChatMode = Self("hermeschat.toggleMode")

    /// Posted when the user triggers the new conversation shortcut
    static let hermesNewChat = Self("hermeschat.newChat")
}